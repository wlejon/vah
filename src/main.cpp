#include <SDL2/SDL.h>
#include <glad/glad.h>
#include <RmlUi/Core.h>
#include <RmlUi/Lua.h>
#include <RmlUi/Lua/Interpreter.h>
#include <RmlUi/Debugger.h>
#include <iostream>
#include <memory>

#include "Logger.h"
#include "RmlUi_Renderer_GL3.h"
#include "RmlUiSystemInterface.h"
#include "CommandQueue.h"
#include "ResponseQueue.h"
#include "Seqlock.h"
#include "InputState.h"
#include "ThreadManager.h"
#include "RmlUiBridge.h"
#include "DataStore.h"
#include "DataBindings.h"

class VahEngine {
public:
    VahEngine() = default;
    ~VahEngine() = default;

    bool Initialize() {
        Logger::Initialize();
        LOG_INFO("Initializing Vah Engine...");

        // Initialize SDL
        if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS) != 0) {
            LOG_ERROR("Failed to initialize SDL: {}", SDL_GetError());
            return false;
        }

        // Create window
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
        SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);

        window_ = SDL_CreateWindow("Vah", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                                   1280, 720, SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE);
        if (!window_) {
            LOG_ERROR("Failed to create window: {}", SDL_GetError());
            return false;
        }

        // Create OpenGL context
        gl_context_ = SDL_GL_CreateContext(window_);
        if (!gl_context_) {
            LOG_ERROR("Failed to create OpenGL context: {}", SDL_GetError());
            return false;
        }

        SDL_GL_MakeCurrent(window_, gl_context_);
        SDL_GL_SetSwapInterval(1); // VSync

        // Initialize GLAD
        if (!gladLoadGLLoader((GLADloadproc)SDL_GL_GetProcAddress)) {
            LOG_ERROR("Failed to initialize GLAD");
            return false;
        }

        // Initialize RmlGL3 helper
        Rml::String rml_message;
        if (!RmlGL3::Initialize(&rml_message)) {
            LOG_ERROR("Failed to initialize RmlGL3: {}", rml_message);
            return false;
        }
        LOG_INFO("RmlGL3: {}", rml_message);

        // Initialize RmlUI renderer
        rml_renderer_ = std::make_unique<RenderInterface_GL3>();

        // Verify renderer was created successfully
        if (!*rml_renderer_) {
            LOG_ERROR("Failed to create RmlUI renderer");
            return false;
        }

        // Initialize RmlUI system interface (for logging and time)
        rml_system_interface_ = std::make_unique<RmlUiSystemInterface>();

        Rml::SetRenderInterface(rml_renderer_.get());
        Rml::SetSystemInterface(rml_system_interface_.get());

        if (!Rml::Initialise()) {
            LOG_ERROR("Failed to initialize RmlUI");
            return false;
        }

        // Load fonts AFTER Rml::Initialise() but BEFORE creating context
        if (!Rml::LoadFontFace("ui/fonts/roboto-static/Roboto-Regular.ttf")) {
            LOG_WARN("Failed to load Roboto Regular font");
        }
        if (!Rml::LoadFontFace("ui/fonts/roboto-static/Roboto-Bold.ttf")) {
            LOG_WARN("Failed to load Roboto Bold font");
        }
        if (!Rml::LoadFontFace("ui/fonts/roboto-static/Roboto-Italic.ttf")) {
            LOG_WARN("Failed to load Roboto Italic font");
        }
        if (!Rml::LoadFontFace("ui/fonts/roboto-static/Roboto-Light.ttf")) {
            LOG_WARN("Failed to load Roboto Light font");
        }
        if (!Rml::LoadFontFace("ui/fonts/roboto-static/Roboto-Medium.ttf")) {
            LOG_WARN("Failed to load Roboto Medium font");
        }

        // Create RmlUI context
        int width, height;
        SDL_GetWindowSize(window_, &width, &height);
        rml_context_ = Rml::CreateContext("main", Rml::Vector2i(width, height));
        if (!rml_context_) {
            LOG_ERROR("Failed to create RmlUI context");
            return false;
        }

        // Initialize RmlUI Lua plugin (creates global lua state)
        Rml::Lua::Initialise();

        // Initialize debugger
        Rml::Debugger::Initialise(rml_context_);

        // Initialize our systems
        command_queue_ = std::make_unique<CommandQueue>();
        input_seqlock_ = std::make_unique<Seqlock<InputState>>();
        data_store_ = std::make_unique<DataStore>();
        thread_manager_ = std::make_unique<ThreadManager>(command_queue_.get(), input_seqlock_.get(), data_store_.get());
        rmlui_bridge_ = std::make_unique<RmlUiBridge>(input_seqlock_.get());

        // Setup RmlUI lua bindings - pass context so we can create data models
        lua_State* rml_lua = Rml::Lua::Interpreter::GetLuaState();

        // Store context in Lua registry for data model creation
        lua_pushlightuserdata(rml_lua, rml_context_);
        lua_setfield(rml_lua, LUA_REGISTRYINDEX, "rmlui_context");

        rmlui_bridge_->SetupLuaBindings(rml_lua, rml_context_);

        // Spawn main Lua thread which will load UI
        thread_manager_->SpawnThread("scripts/main.lua");

        LOG_INFO("Vah Engine initialized successfully");
        return true;
    }

    void Run() {
        running_ = true;
        uint64_t frame_number = 0;

        while (running_) {
            ProcessInput();
            ProcessCommands();
            Update();
            Render();

            frame_number++;
        }
    }

    void Shutdown() {
        LOG_INFO("Shutting down Vah Engine...");

        // Clean up data model definitions before context is destroyed
        data_model_defs_.clear();

        thread_manager_.reset();
        rmlui_bridge_.reset();
        data_store_.reset();
        input_seqlock_.reset();
        command_queue_.reset();

        if (rml_context_) {
            rml_context_->UnloadAllDocuments();
            rml_context_ = nullptr;
        }

        Rml::Shutdown();

        rml_system_interface_.reset();
        rml_renderer_.reset();
        RmlGL3::Shutdown();

        if (gl_context_) {
            SDL_GL_DeleteContext(gl_context_);
            gl_context_ = nullptr;
        }

        if (window_) {
            SDL_DestroyWindow(window_);
            window_ = nullptr;
        }

        SDL_Quit();
        Logger::Shutdown();
    }

private:
    void ProcessInput() {
        SDL_Event event;

        // Start with fresh state for this frame
        InputState current_state;
        auto old_state = input_seqlock_->Read();
        current_state.frame_number = old_state.frame_number + 1;

        // DON'T clear events yet - let worker threads read them first

        // Get actual SDL mouse and keyboard state (not from events)
        int mouse_x, mouse_y;
        Uint32 mouse_buttons = SDL_GetMouseState(&mouse_x, &mouse_y);
        current_state.mouse_x = mouse_x;
        current_state.mouse_y = mouse_y;
        current_state.mouse_left = (mouse_buttons & SDL_BUTTON(SDL_BUTTON_LEFT)) != 0;
        current_state.mouse_right = (mouse_buttons & SDL_BUTTON(SDL_BUTTON_RIGHT)) != 0;
        current_state.mouse_middle = (mouse_buttons & SDL_BUTTON(SDL_BUTTON_MIDDLE)) != 0;

        // Get keyboard state
        const Uint8* keyboard_state = SDL_GetKeyboardState(nullptr);
        // Copy previous frame's keyboard state
        current_state.keyboard = old_state.keyboard;

        // Process SDL events
        while (SDL_PollEvent(&event)) {
            switch (event.type) {
                case SDL_QUIT:
                    running_ = false;
                    break;

                case SDL_KEYDOWN:
                    current_state.keyboard[SDL_GetKeyName(event.key.keysym.sym)] = true;
                    current_state.key_events.push_back({SDL_GetKeyName(event.key.keysym.sym), true});
                    if (event.key.keysym.sym == SDLK_ESCAPE) {
                        running_ = false;
                    }
                    break;

                case SDL_KEYUP:
                    current_state.keyboard[SDL_GetKeyName(event.key.keysym.sym)] = false;
                    current_state.key_events.push_back({SDL_GetKeyName(event.key.keysym.sym), false});
                    break;

                case SDL_MOUSEBUTTONDOWN:
                    {
                        MouseButton btn = MouseButton::Left;
                        if (event.button.button == SDL_BUTTON_LEFT) btn = MouseButton::Left;
                        else if (event.button.button == SDL_BUTTON_RIGHT) btn = MouseButton::Right;
                        else if (event.button.button == SDL_BUTTON_MIDDLE) btn = MouseButton::Middle;
                        current_state.mouse_button_events.push_back({btn, event.button.x, event.button.y, true});
                    }
                    break;

                case SDL_MOUSEBUTTONUP:
                    {
                        MouseButton btn = MouseButton::Left;
                        if (event.button.button == SDL_BUTTON_LEFT) btn = MouseButton::Left;
                        else if (event.button.button == SDL_BUTTON_RIGHT) btn = MouseButton::Right;
                        else if (event.button.button == SDL_BUTTON_MIDDLE) btn = MouseButton::Middle;
                        current_state.mouse_button_events.push_back({btn, event.button.x, event.button.y, false});
                    }
                    break;

                case SDL_MOUSEMOTION:
                    current_state.mouse_move_events.push_back({
                        event.motion.x,
                        event.motion.y,
                        event.motion.xrel,
                        event.motion.yrel
                    });
                    break;

                case SDL_WINDOWEVENT:
                    if (event.window.event == SDL_WINDOWEVENT_RESIZED) {
                        int width = event.window.data1;
                        int height = event.window.data2;
                        rml_renderer_->SetViewport(width, height);
                        if (rml_context_) {
                            rml_context_->SetDimensions(Rml::Vector2i(width, height));
                        }
                    }
                    break;
            }

            // Pass events to RmlUI
            if (rml_context_) {
                switch (event.type) {
                    case SDL_MOUSEBUTTONDOWN:
                        rml_context_->ProcessMouseButtonDown(event.button.button - 1, 0);
                        break;
                    case SDL_MOUSEBUTTONUP:
                        rml_context_->ProcessMouseButtonUp(event.button.button - 1, 0);
                        break;
                    case SDL_MOUSEMOTION:
                        rml_context_->ProcessMouseMove(event.motion.x, event.motion.y, 0);
                        break;
                    case SDL_MOUSEWHEEL:
                        rml_context_->ProcessMouseWheel(static_cast<float>(-event.wheel.y), 0);
                        break;
                    case SDL_TEXTINPUT:
                        // Convert UTF-8 text to unicode codepoints for RmlUI
                        for (char* c = event.text.text; *c; c++) {
                            if ((*c & 0x80) == 0) {
                                rml_context_->ProcessTextInput(static_cast<Rml::Character>(*c));
                            }
                        }
                        break;
                }
            }
        }

        // Check if any UI events were triggered during SDL processing
        // (RmlUiBridge writes directly to seqlock when trigger() is called)
        auto state_after_triggers = input_seqlock_->Read();

        // Copy any UI events that were added by trigger() during this frame
        if (!state_after_triggers.ui_events.empty()) {
            current_state.ui_events = state_after_triggers.ui_events;
        }

        // Write updated input state to seqlock
        // Events will persist until next frame, giving worker threads time to read them
        input_seqlock_->Write(current_state);
    }

    void ProcessCommands() {
        command_queue_->ProcessAll([this](const Command& cmd) {
            std::visit([this](auto&& command) {
                using T = std::decay_t<decltype(command)>;

                if constexpr (std::is_same_v<T, Commands::SpawnThread>) {
                    LOG_INFO("Processing SpawnThread command: {} (parent: {})", command.script_path, command.parent_thread_id);
                    if (command.parent_thread_id != 0) {
                        thread_manager_->SpawnThread(command.script_path, command.parent_thread_id, command.parent_request_id);
                    } else {
                        thread_manager_->SpawnThread(command.script_path);
                    }
                }
                else if constexpr (std::is_same_v<T, Commands::StopThread>) {
                    LOG_INFO("Processing StopThread command: {}", command.thread_id);
                    thread_manager_->StopThread(command.thread_id);
                }
                else if constexpr (std::is_same_v<T, Commands::TriggerUI>) {
                    LOG_INFO("Processing TriggerUI command: {}", command.event_name);
                    // UI events are already handled by RmlUiBridge
                }
                else if constexpr (std::is_same_v<T, Commands::CallMainThread>) {
                    command.callback();
                }
                else if constexpr (std::is_same_v<T, Commands::SaveThread>) {
                    LOG_INFO("Processing SaveThread command: {} -> {}", command.thread_id, command.save_path);
                    thread_manager_->SaveThread(command.thread_id, command.save_path);
                }
                else if constexpr (std::is_same_v<T, Commands::Print>) {
                    LOG_INFO("[Lua Thread {}] {}", command.thread_id, command.message);
                }
                else if constexpr (std::is_same_v<T, Commands::SendResponse>) {
                    LOG_DEBUG("Processing SendResponse command to thread {}", command.target_thread_id);
                    auto response_queue = thread_manager_->GetThreadResponseQueue(command.target_thread_id);
                    if (response_queue) {
                        response_queue->Push(Response{command.request_id, command.data, command.error});
                    } else {
                        LOG_WARN("Cannot send response to thread {}: thread not found", command.target_thread_id);
                    }
                }
                else if constexpr (std::is_same_v<T, Commands::LoadUIDocument>) {
                    LOG_INFO("Processing LoadUIDocument command: {}", command.document_path);
                    auto doc = rml_context_->LoadDocument(command.document_path.c_str());
                    if (doc) {
                        // Store document if ID provided
                        if (!command.document_id.empty()) {
                            loaded_documents_[command.document_id] = doc;
                            LOG_INFO("Stored document with ID: {}", command.document_id);
                        }

                        if (command.show) {
                            doc->Show();
                        } else {
                            doc->Hide();
                        }
                        LOG_INFO("Loaded UI document: {}", command.document_path);
                    } else {
                        LOG_WARN("Failed to load UI document: {}", command.document_path);
                    }
                }
                else if constexpr (std::is_same_v<T, Commands::ShowUIDocument>) {
                    auto it = loaded_documents_.find(command.document_id);
                    if (it != loaded_documents_.end()) {
                        it->second->Show();
                        LOG_INFO("Showing document: {}", command.document_id);
                    } else {
                        LOG_WARN("Document not found: {}", command.document_id);
                    }
                }
                else if constexpr (std::is_same_v<T, Commands::HideUIDocument>) {
                    auto it = loaded_documents_.find(command.document_id);
                    if (it != loaded_documents_.end()) {
                        it->second->Hide();
                        LOG_INFO("Hiding document: {}", command.document_id);
                    } else {
                        LOG_WARN("Document not found: {}", command.document_id);
                    }
                }
                else if constexpr (std::is_same_v<T, Commands::SetElementText>) {
                    if (rml_context_) {
                        // Search all documents for the element
                        for (int i = 0; i < rml_context_->GetNumDocuments(); i++) {
                            auto doc = rml_context_->GetDocument(i);
                            if (doc) {
                                auto element = doc->GetElementById(command.element_id.c_str());
                                if (element) {
                                    element->SetInnerRML(command.text.c_str());
                                    break;
                                }
                            }
                        }
                    }
                }
                else if constexpr (std::is_same_v<T, Commands::SetElementAttribute>) {
                    if (rml_context_) {
                        for (int i = 0; i < rml_context_->GetNumDocuments(); i++) {
                            auto doc = rml_context_->GetDocument(i);
                            if (doc) {
                                auto element = doc->GetElementById(command.element_id.c_str());
                                if (element) {
                                    element->SetAttribute(command.attribute_name.c_str(), command.value.c_str());
                                    break;
                                }
                            }
                        }
                    }
                }
                else if constexpr (std::is_same_v<T, Commands::SetElementStyle>) {
                    if (rml_context_) {
                        for (int i = 0; i < rml_context_->GetNumDocuments(); i++) {
                            auto doc = rml_context_->GetDocument(i);
                            if (doc) {
                                auto element = doc->GetElementById(command.element_id.c_str());
                                if (element) {
                                    element->SetProperty(command.property.c_str(), command.value.c_str());
                                    break;
                                }
                            }
                        }
                    }
                }
                else if constexpr (std::is_same_v<T, Commands::AddElementClass>) {
                    if (rml_context_) {
                        for (int i = 0; i < rml_context_->GetNumDocuments(); i++) {
                            auto doc = rml_context_->GetDocument(i);
                            if (doc) {
                                auto element = doc->GetElementById(command.element_id.c_str());
                                if (element) {
                                    element->SetClass(command.class_name.c_str(), true);
                                    break;
                                }
                            }
                        }
                    }
                }
                else if constexpr (std::is_same_v<T, Commands::RemoveElementClass>) {
                    if (rml_context_) {
                        for (int i = 0; i < rml_context_->GetNumDocuments(); i++) {
                            auto doc = rml_context_->GetDocument(i);
                            if (doc) {
                                auto element = doc->GetElementById(command.element_id.c_str());
                                if (element) {
                                    element->SetClass(command.class_name.c_str(), false);
                                    break;
                                }
                            }
                        }
                    }
                }
                else if constexpr (std::is_same_v<T, Commands::BindDataModel>) {
                    LOG_INFO("Processing BindDataModel command: {}", command.model_name);

                    if (rml_context_ && data_store_) {
                        // Create a data model in RmlUi
                        Rml::DataModelConstructor constructor = rml_context_->CreateDataModel(command.model_name);

                        if (constructor) {
                            // Create our custom variable definition
                            auto table_def = std::make_unique<DynamicTableDef>(data_store_.get(), command.model_name);

                            // Bind the model (using nullptr as root pointer for the whole table)
                            constructor.BindCustomDataVariable(command.model_name, Rml::DataVariable(table_def.get(), nullptr));

                            // Register event callbacks that use RmlUI's Lua state
                            // These callbacks can access the global trigger_delete function
                            constructor.BindEventCallback("trigger_delete", [](Rml::DataModelHandle, Rml::Event&, const Rml::VariantList& arguments) {
                                if (arguments.size() >= 1) {
                                    // Get the Lua state and call the global trigger_delete function
                                    lua_State* L = Rml::Lua::Interpreter::GetLuaState();
                                    lua_getglobal(L, "trigger_delete");
                                    if (lua_isfunction(L, -1)) {
                                        // Push the contact ID argument
                                        if (arguments[0].GetType() == Rml::Variant::INT) {
                                            lua_pushinteger(L, arguments[0].Get<int>());
                                        } else if (arguments[0].GetType() == Rml::Variant::INT64) {
                                            lua_pushinteger(L, arguments[0].Get<int64_t>());
                                        } else if (arguments[0].GetType() == Rml::Variant::FLOAT) {
                                            lua_pushinteger(L, static_cast<int>(arguments[0].Get<float>()));
                                        } else {
                                            lua_pushinteger(L, 0);
                                        }
                                        // Call the function
                                        lua_pcall(L, 1, 0, 0);
                                    } else {
                                        lua_pop(L, 1);
                                    }
                                }
                            });

                            // Store the definition so it stays alive
                            data_model_defs_[command.model_name] = std::move(table_def);

                            // Get and store the model handle
                            data_model_handles_[command.model_name] = constructor.GetModelHandle();

                            LOG_INFO("Successfully bound data model '{}'", command.model_name);
                        } else {
                            LOG_WARN("Failed to create data model '{}'", command.model_name);
                        }
                    }
                }
                else if constexpr (std::is_same_v<T, Commands::DirtyDataModel>) {
                    LOG_DEBUG("Processing DirtyDataModel command: {}", command.model_name);

                    // Mark the model as dirty so RmlUi re-renders
                    auto it = data_model_handles_.find(command.model_name);
                    if (it != data_model_handles_.end()) {
                        it->second.DirtyVariable(command.model_name);
                        LOG_DEBUG("Marked data model '{}' as dirty", command.model_name);
                    } else {
                        LOG_WARN("Data model '{}' not found for dirty marking", command.model_name);
                    }
                }

            }, cmd);
        });
    }

    void Update() {
        if (rml_context_) {
            rml_context_->Update();
        }
    }

    void Render() {
        // Get window size
        int width, height;
        SDL_GetWindowSize(window_, &width, &height);

        // Set viewport BEFORE BeginFrame
        rml_renderer_->SetViewport(width, height);

        rml_renderer_->BeginFrame();
        rml_renderer_->Clear();

        if (rml_context_) {
            rml_context_->Render();
        }

        rml_renderer_->EndFrame();
        SDL_GL_SwapWindow(window_);
    }

    bool running_ = false;
    SDL_Window* window_ = nullptr;
    SDL_GLContext gl_context_ = nullptr;

    std::unique_ptr<RenderInterface_GL3> rml_renderer_;
    std::unique_ptr<RmlUiSystemInterface> rml_system_interface_;
    Rml::Context* rml_context_ = nullptr;

    std::unique_ptr<CommandQueue> command_queue_;
    std::unique_ptr<Seqlock<InputState>> input_seqlock_;
    std::unique_ptr<DataStore> data_store_;
    std::unique_ptr<ThreadManager> thread_manager_;
    std::unique_ptr<RmlUiBridge> rmlui_bridge_;

    // Track loaded documents by ID
    std::unordered_map<std::string, Rml::ElementDocument*> loaded_documents_;

    // Track data models and their definitions
    std::unordered_map<std::string, std::unique_ptr<DynamicTableDef>> data_model_defs_;
    std::unordered_map<std::string, Rml::DataModelHandle> data_model_handles_;
};

int main(int argc, char* argv[]) {
    VahEngine engine;

    if (!engine.Initialize()) {
        std::cerr << "Failed to initialize Vah Engine" << std::endl;
        return -1;
    }

    try {
        engine.Run();
    }
    catch (const std::exception& e) {
        std::cerr << "Runtime error: " << e.what() << std::endl;
        LOG_CRITICAL("Runtime error: {}", e.what());
        return -1;
    }

    engine.Shutdown();
    return 0;
}
