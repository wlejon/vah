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
#include <moodycamel/concurrentqueue.h>
#include "Commands.h"
#include "InputState.h"
#include "ThreadManager.h"
#include "RmlUiBridge.h"
#include "DataStore.h"
#include "DataBindings.h"
#include "InputEventListener.h"
#include "InputTracker.h"
#include "DocumentManager.h"
#include "DataModelManager.h"
#include "CommandProcessor.h"
#include <efsw/efsw.hpp>

// File watcher listener for RML/RCSS hot reload
class UIFileWatchListener : public efsw::FileWatchListener {
public:
    UIFileWatchListener(moodycamel::ConcurrentQueue<Command>* command_queue) : command_queue_(command_queue) {}

    void handleFileAction(efsw::WatchID watch_id,
                         const std::string& dir,
                         const std::string& filename,
                         efsw::Action action,
                         std::string old_filename) override {

        // Only respond to modifications and additions
        if (action != efsw::Actions::Modified && action != efsw::Actions::Add) {
            return;
        }

        // Check if it's an RML or RCSS file
        std::string lower_filename = filename;
        std::transform(lower_filename.begin(), lower_filename.end(), lower_filename.begin(), ::tolower);

        if (lower_filename.ends_with(".rml") || lower_filename.ends_with(".rcss")) {
            std::string full_path = dir + filename;
            LOG_INFO("UI file changed, reloading: {}", full_path);

            // Push file changed command for both RML and RCSS
            Commands::FileChanged cmd;
            cmd.path = full_path;
            cmd.event_type = "modified";
            command_queue_->enqueue(std::move(cmd));
        }
    }

private:
    moodycamel::ConcurrentQueue<Command>* command_queue_;
};

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
        command_queue_ = std::make_unique<moodycamel::ConcurrentQueue<Command>>();
        ui_event_queue_ = std::make_unique<moodycamel::ConcurrentQueue<UIEvent>>();
        data_store_ = std::make_unique<DataStore>();
        thread_manager_ = std::make_unique<ThreadManager>(command_queue_.get(), ui_event_queue_.get(), data_store_.get());
        rmlui_bridge_ = std::make_unique<RmlUiBridge>(ui_event_queue_.get());

        // Initialize managers
        document_manager_ = std::make_unique<DocumentManager>(rml_context_);
        data_model_manager_ = std::make_unique<DataModelManager>(rml_context_, data_store_.get(), ui_event_queue_.get());

        // Initialize input tracker
        input_tracker_ = std::make_unique<InputTracker>();
        input_tracker_->Initialize("data/input_tracking.db");

        // Initialize command processor (needs all managers and input tracker)
        command_processor_ = std::make_unique<CommandProcessor>(
            thread_manager_.get(),
            document_manager_.get(),
            data_model_manager_.get(),
            input_tracker_.get()
        );

        // Initialize input event listener for automatic tracking
        input_event_listener_ = std::make_unique<InputEventListener>();

        // Setup callbacks - wire InputEventListener to InputTracker
        input_event_listener_->SetOnFocus([this](const std::string& model, const std::string& record_id,
                                                  const std::string& field, const std::string& value) {
            if (input_tracker_) {
                input_tracker_->OnFocus(model, record_id, field, value);
            }
        });

        input_event_listener_->SetOnBlur([this](const std::string& model, const std::string& record_id,
                                                 const std::string& field, const std::string& value) {
            if (input_tracker_) {
                input_tracker_->OnBlur(model, record_id, field, value);
            }
        });

        input_event_listener_->SetOnChange([this](const std::string& model, const std::string& record_id,
                                                   const std::string& field, const std::string& value) {
            if (input_tracker_) {
                input_tracker_->OnChange(model, record_id, field, value);
            }
        });

        // Register the listener with the RmlUi context for all three event types
        // Use capture phase (true) to catch events before they bubble
        rml_context_->AddEventListener("focus", input_event_listener_.get(), true);
        rml_context_->AddEventListener("blur", input_event_listener_.get(), true);
        rml_context_->AddEventListener("change", input_event_listener_.get(), true);

        // Setup RmlUI lua bindings - pass context so we can create data models
        lua_State* rml_lua = Rml::Lua::Interpreter::GetLuaState();

        // Store context in Lua registry for data model creation
        lua_pushlightuserdata(rml_lua, rml_context_);
        lua_setfield(rml_lua, LUA_REGISTRYINDEX, "rmlui_context");

        rmlui_bridge_->SetupLuaBindings(rml_lua, rml_context_);

        // Spawn main Lua thread which will load UI
        thread_manager_->SpawnThread("scripts/main.lua");

        // Setup file watcher for RML/RCSS hot reload
        ui_file_watcher_ = std::make_unique<efsw::FileWatcher>();
        ui_file_watch_listener_ = std::make_unique<UIFileWatchListener>(command_queue_.get());

        // Watch the ui directory recursively
        efsw::WatchID watch_id = ui_file_watcher_->addWatch("ui", ui_file_watch_listener_.get(), true);
        if (watch_id >= 0) {
            ui_file_watcher_->watch();
            LOG_INFO("Watching ui/ directory for RML/RCSS changes");
        } else {
            LOG_WARN("Failed to watch ui/ directory for hot reload");
        }

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

        // Stop file watcher
        ui_file_watch_listener_.reset();
        ui_file_watcher_.reset();

        // Shutdown managers (in reverse order of initialization)
        command_processor_.reset();

        // Unregister input event listener before destroying context
        if (rml_context_ && input_event_listener_) {
            rml_context_->RemoveEventListener("focus", input_event_listener_.get(), true);
            rml_context_->RemoveEventListener("blur", input_event_listener_.get(), true);
            rml_context_->RemoveEventListener("change", input_event_listener_.get(), true);
        }

        thread_manager_.reset();
        rmlui_bridge_.reset();
        input_event_listener_.reset();
        input_tracker_.reset();

        // Clean up managers before destroying context
        data_model_manager_.reset();
        document_manager_.reset();

        data_store_.reset();
        ui_event_queue_.reset();
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

        while (SDL_PollEvent(&event)) {
            switch (event.type) {
                case SDL_QUIT:
                    running_ = false;
                    break;

                case SDL_KEYDOWN:
                    if (event.key.keysym.sym == SDLK_ESCAPE) {
                        running_ = false;
                    }
                    // Handle Ctrl+V for clipboard paste
                    else if (event.key.keysym.sym == SDLK_v && (event.key.keysym.mod & KMOD_CTRL)) {
                        if (SDL_HasClipboardText()) {
                            char* clipboard_text = SDL_GetClipboardText();
                            if (clipboard_text) {
                                std::string text(clipboard_text);
                                SDL_free(clipboard_text);

                                LOG_INFO("Clipboard paste detected ({} bytes)", text.size());
                                // Trigger UI event with clipboard text
                                PayloadMap payload;
                                payload["text"] = text;
                                ui_event_queue_->enqueue(UIEvent{"clipboard_paste", payload});
                            }
                        }
                    }
                    break;

                case SDL_DROPFILE:
                    // Handle file drag and drop
                    if (event.drop.file) {
                        std::string dropped_file(event.drop.file);
                        SDL_free(event.drop.file);

                        LOG_INFO("File drop detected: {}", dropped_file);
                        // Trigger UI event with file path
                        PayloadMap payload;
                        payload["path"] = dropped_file;
                        ui_event_queue_->enqueue(UIEvent{"file_drop", payload});
                    }
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
                        for (char* c = event.text.text; *c; c++) {
                            if ((*c & 0x80) == 0) {
                                rml_context_->ProcessTextInput(static_cast<Rml::Character>(*c));
                            }
                        }
                        break;
                }
            }
        }
    }

    void ProcessCommands() {
        // Dequeue all pending commands
        std::vector<Command> commands;
        Command cmd;
        while (command_queue_->try_dequeue(cmd)) {
            commands.push_back(std::move(cmd));
        }

        // Process each command
        for (const auto& cmd : commands) {
            // Handle FileChanged specially (needs custom path processing logic)
            if (std::holds_alternative<Commands::FileChanged>(cmd)) {
                const auto& command = std::get<Commands::FileChanged>(cmd);

                if (command.event_type == "modified" && document_manager_) {
                    std::string lower_path = command.path;
                    std::transform(lower_path.begin(), lower_path.end(), lower_path.begin(), ::tolower);

                    // Normalize path separators to forward slashes
                    std::string normalized_path = command.path;
                    std::replace(normalized_path.begin(), normalized_path.end(), '\\', '/');

                    if (lower_path.ends_with(".rml")) {
                        document_manager_->HandleRmlFileChanged(normalized_path);
                    } else if (lower_path.ends_with(".rcss")) {
                        LOG_INFO("RCSS file changed: {}, clearing cache and reloading all documents", command.path);
                        document_manager_->HandleRcssFileChanged();
                    }
                }
            } else {
                // Delegate all other commands to CommandProcessor
                command_processor_->ProcessCommand(cmd);
            }
        }
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

    std::unique_ptr<moodycamel::ConcurrentQueue<Command>> command_queue_;
    std::unique_ptr<moodycamel::ConcurrentQueue<UIEvent>> ui_event_queue_;
    std::unique_ptr<DataStore> data_store_;
    std::unique_ptr<ThreadManager> thread_manager_;
    std::unique_ptr<RmlUiBridge> rmlui_bridge_;
    std::unique_ptr<InputEventListener> input_event_listener_;
    std::unique_ptr<InputTracker> input_tracker_;

    // Managers
    std::unique_ptr<DocumentManager> document_manager_;
    std::unique_ptr<DataModelManager> data_model_manager_;
    std::unique_ptr<CommandProcessor> command_processor_;

    // File watcher for RML/RCSS hot reload
    std::unique_ptr<efsw::FileWatcher> ui_file_watcher_;
    std::unique_ptr<UIFileWatchListener> ui_file_watch_listener_;
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
