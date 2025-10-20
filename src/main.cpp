#include <SDL2/SDL.h>
#include <glad/glad.h>
#include <RmlUi/Core.h>
#include <RmlUi/Lua.h>
#include <RmlUi/Lua/Interpreter.h>
#include <RmlUi/Debugger.h>
#include <iostream>
#include <memory>
#include <filesystem>

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
#include "DocumentManager.h"
#include "DataModelManager.h"
#include "CommandProcessor.h"
#include "ElementCanvas.h"
#include "ElementTextEditor.h"
#include "ElementTextEditorInstancer.h"
#include "NanoVGBindings.h"
#include "NotificationFeed.h"
#include "NotificationBindings.h"
#include "NotificationPlugin.h"
#include "EventDispatcher.h"
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

        // Check if it's an RML, RCSS, or LUA file
        std::string lower_filename = filename;
        std::transform(lower_filename.begin(), lower_filename.end(), lower_filename.begin(), ::tolower);

        if (lower_filename.ends_with(".rml") || lower_filename.ends_with(".rcss") || lower_filename.ends_with(".lua")) {
            std::string full_path = dir + filename;
            LOG_INFO("UI file changed, reloading: {}", full_path);

            // Push file changed command for RML, RCSS, and Lua
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
        if (!Rml::LoadFontFace("ui/fonts/jetbrains-mono-static/JetBrainsMono-Regular.ttf")) {
            LOG_WARN("Failed to load JetBrains Mono font");
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

        // Register custom elements
        canvas_instancer_ = std::make_unique<Rml::ElementInstancerGeneric<ElementCanvas>>();
        Rml::Factory::RegisterElementInstancer("canvas", canvas_instancer_.get());
        LOG_INFO("Registered custom element: canvas");

        texteditor_instancer_ = std::make_unique<ElementTextEditorInstancer>();
        Rml::Factory::RegisterElementInstancer("texteditor", texteditor_instancer_.get());
        LOG_INFO("Registered custom element: texteditor");

        // Setup Lua bindings for TextEditor element
        // RmlUI Lua will automatically expose elements retrieved via GetElementById
        // We need to register custom methods for ElementTextEditor
        lua_State* rml_lua_early = Rml::Lua::Interpreter::GetLuaState();
        if (rml_lua_early) {
            // Register custom methods on Element metatable for texteditor elements
            // This will be accessible when element is retrieved via document:GetElementById()

            // Get the Element metatable
            luaL_getmetatable(rml_lua_early, "Rml::Element");
            if (lua_istable(rml_lua_early, -1)) {
                // Register SetText method
                lua_pushstring(rml_lua_early, "SetText");
                lua_pushcfunction(rml_lua_early, [](lua_State* L) -> int {
                    Rml::Element* elem = Rml::Lua::LuaType<Rml::Element>::check(L, 1);
                    const char* text = luaL_checkstring(L, 2);

                    ElementTextEditor* editor = dynamic_cast<ElementTextEditor*>(elem);
                    if (editor) {
                        editor->SetText(text);
                    }
                    return 0;
                });
                lua_settable(rml_lua_early, -3);

                // Register GetText method
                lua_pushstring(rml_lua_early, "GetText");
                lua_pushcfunction(rml_lua_early, [](lua_State* L) -> int {
                    Rml::Element* elem = Rml::Lua::LuaType<Rml::Element>::check(L, 1);

                    ElementTextEditor* editor = dynamic_cast<ElementTextEditor*>(elem);
                    if (editor) {
                        std::string text = editor->GetText();
                        lua_pushstring(L, text.c_str());
                        return 1;
                    }
                    return 0;
                });
                lua_settable(rml_lua_early, -3);

                // Register GetSelectedText method
                lua_pushstring(rml_lua_early, "GetSelectedText");
                lua_pushcfunction(rml_lua_early, [](lua_State* L) -> int {
                    Rml::Element* elem = Rml::Lua::LuaType<Rml::Element>::check(L, 1);

                    ElementTextEditor* editor = dynamic_cast<ElementTextEditor*>(elem);
                    if (editor) {
                        std::string text = editor->GetSelectedText();
                        lua_pushstring(L, text.c_str());
                        return 1;
                    }
                    return 0;
                });
                lua_settable(rml_lua_early, -3);

                // Note: SetSyntaxHighlighter is now handled through the command system
                // via ui.set_texteditor_content() in LuaThread
            }
            lua_pop(rml_lua_early, 1); // Pop metatable

            LOG_INFO("Registered Lua bindings for ElementTextEditor");
        }

        // Initialize our systems
        command_queue_ = std::make_unique<moodycamel::ConcurrentQueue<Command>>();
        event_dispatcher_ = std::make_unique<EventDispatcher>();
        data_store_ = std::make_unique<DataStore>();
        notification_feed_ = std::make_unique<NotificationFeed>();
        thread_manager_ = std::make_unique<ThreadManager>(command_queue_.get(), event_dispatcher_.get(), data_store_.get(), notification_feed_.get());
        rmlui_bridge_ = std::make_unique<RmlUiBridge>(event_dispatcher_.get());

        // Initialize managers
        document_manager_ = std::make_unique<DocumentManager>(rml_context_, rmlui_bridge_.get());
        data_model_manager_ = std::make_unique<DataModelManager>(rml_context_, data_store_.get(), event_dispatcher_.get());

        // Initialize command processor (needs all managers)
        command_processor_ = std::make_unique<CommandProcessor>(
            thread_manager_.get(),
            document_manager_.get(),
            data_model_manager_.get(),
            notification_feed_.get(),
            event_dispatcher_.get()
        );

        // Setup RmlUI lua bindings - pass context so we can create data models
        lua_State* rml_lua = Rml::Lua::Interpreter::GetLuaState();

        // Add ui/ folder to Lua package path for require() in RML scripts
        lua_getglobal(rml_lua, "package");
        lua_getfield(rml_lua, -1, "path");
        std::string current_path = lua_tostring(rml_lua, -1);
        std::string new_path = current_path + ";ui/?.lua";
        lua_pop(rml_lua, 1);
        lua_pushstring(rml_lua, new_path.c_str());
        lua_setfield(rml_lua, -2, "path");
        lua_pop(rml_lua, 1);

        // Store context in Lua registry for data model creation
        lua_pushlightuserdata(rml_lua, rml_context_);
        lua_setfield(rml_lua, LUA_REGISTRYINDEX, "rmlui_context");

        // Setup NanoVG bindings for canvas elements
        NanoVGBindings::SetupBindings(rml_lua);

        rmlui_bridge_->SetupLuaBindings(rml_lua, rml_context_, data_store_.get());

        // Setup global notification feed reference for Lua callbacks
        extern NotificationFeed* g_notification_feed;
        g_notification_feed = notification_feed_.get();

        // Register notification data model with RmlUi
        Rml::DataModelConstructor notif_constructor = rml_context_->CreateDataModel("notifications");
        if (auto notif_handle = notif_constructor.RegisterStruct<Notification>()) {
            notif_handle.RegisterMember("id", &Notification::id);
            notif_handle.RegisterMember("type", &Notification::type);
            notif_handle.RegisterMember("title", &Notification::title);
            notif_handle.RegisterMember("message", &Notification::message);
            notif_handle.RegisterMember("thread_name", &Notification::thread_name);
            notif_handle.RegisterMember("timestamp", &Notification::timestamp);
            notif_handle.RegisterMember("dismissible", &Notification::dismissible);
            notif_handle.RegisterMember("expandable", &Notification::expandable);
            notif_handle.RegisterMember("expanded_content", &Notification::expanded_content);
            notif_handle.RegisterMember("ttl_seconds", &Notification::ttl_seconds);
        }
        notif_constructor.RegisterArray<std::vector<Notification>>();

        // Bind directly to NotificationFeed's internal vector (no cache!)
        notif_constructor.Bind("notifications", &notification_feed_->GetNotifications());
        notif_constructor.Bind("count", &notification_count_);

        notif_model_handle_ = notif_constructor.GetModelHandle();

        // Setup callback to mark dirty when notifications change
        notification_feed_->SetOnChangeCallback([this]() {
            // Update count
            notification_count_ = notification_feed_->GetCount();

            // Mark dirty so RmlUi knows to re-render
            if (notif_model_handle_) {
                notif_model_handle_.DirtyVariable("notifications");
                notif_model_handle_.DirtyVariable("count");
            }
        });

        // Initialize notification overlay (global, always visible)
        if (!NotificationOverlay::Initialise(rml_context_, notification_feed_.get(),
                                            &notif_model_handle_)) {
            LOG_ERROR("Failed to initialize notification overlay");
        } else {
            // Show the notification overlay
            NotificationOverlay::SetVisible(true);
            LOG_INFO("Notification overlay initialized and visible");
        }

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

        // Shutdown notification overlay
        NotificationOverlay::Shutdown();

        // Stop file watcher
        ui_file_watch_listener_.reset();
        ui_file_watcher_.reset();

        // Shutdown managers (in reverse order of initialization)
        command_processor_.reset();
        thread_manager_.reset();
        rmlui_bridge_.reset();

        // Clean up managers before destroying context
        data_model_manager_.reset();
        document_manager_.reset();

        data_store_.reset();
        event_dispatcher_.reset();
        command_queue_.reset();

        if (rml_context_) {
            rml_context_->UnloadAllDocuments();
            rml_context_ = nullptr;
        }

        // Shutdown debugger before RmlUi
        Rml::Debugger::Shutdown();

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
            if (!rml_context_) {
                running_ = false;
                break;
            }

            switch (event.type) {
                case SDL_QUIT:
                    running_ = false;
                    break;
                case SDL_MOUSEBUTTONDOWN: {
                    auto hover_elem = rml_context_->GetHoverElement();
                    if (hover_elem) {
                        auto class_attr = hover_elem->GetAttribute("class");
                        auto click_attr = hover_elem->GetAttribute("data-event-click");
                        std::string classes = class_attr ? class_attr->Get<Rml::String>() : "";
                        std::string click_handler = click_attr ? click_attr->Get<Rml::String>() : "";
                        LOG_INFO("Click: tag={}, id='{}', class='{}', click='{}'",
                            hover_elem->GetTagName().c_str(),
                            hover_elem->GetId().c_str(),
                            classes.c_str(),
                            click_handler.c_str());
                    } else {
                        LOG_WARN("Click: NO hover element!");
                    }
                    rml_context_->ProcessMouseButtonDown(event.button.button - 1, 0);
                    break;
                }
                case SDL_MOUSEBUTTONUP: {
                    auto hover_elem = rml_context_->GetHoverElement();
                    if (hover_elem) {
                        auto class_attr = hover_elem->GetAttribute("class");
                        std::string classes = class_attr ? class_attr->Get<Rml::String>() : "";
                        LOG_INFO("MouseUp: tag={}, class='{}'", hover_elem->GetTagName().c_str(), classes.c_str());
                    }
                    rml_context_->ProcessMouseButtonUp(event.button.button - 1, 0);
                    break;
                }
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
                case SDL_KEYDOWN:
                case SDL_KEYUP: {
                    // Convert SDL key to RmlUI KeyIdentifier
                    Rml::Input::KeyIdentifier key_id = Rml::Input::KI_UNKNOWN;
                    int key_modifier = 0;

                    // Map common keys
                    switch (event.key.keysym.sym) {
                        // Arrow keys
                        case SDLK_LEFT:     key_id = Rml::Input::KI_LEFT; break;
                        case SDLK_RIGHT:    key_id = Rml::Input::KI_RIGHT; break;
                        case SDLK_UP:       key_id = Rml::Input::KI_UP; break;
                        case SDLK_DOWN:     key_id = Rml::Input::KI_DOWN; break;

                        // Special keys
                        case SDLK_SPACE:    key_id = Rml::Input::KI_SPACE; break;
                        case SDLK_RETURN:   key_id = Rml::Input::KI_RETURN; break;
                        case SDLK_ESCAPE:   key_id = Rml::Input::KI_ESCAPE; break;
                        case SDLK_BACKSPACE: key_id = Rml::Input::KI_BACK; break;
                        case SDLK_TAB:      key_id = Rml::Input::KI_TAB; break;
                        case SDLK_DELETE:   key_id = Rml::Input::KI_DELETE; break;
                        case SDLK_INSERT:   key_id = Rml::Input::KI_INSERT; break;
                        case SDLK_HOME:     key_id = Rml::Input::KI_HOME; break;
                        case SDLK_END:      key_id = Rml::Input::KI_END; break;
                        case SDLK_PAGEUP:   key_id = Rml::Input::KI_PRIOR; break;
                        case SDLK_PAGEDOWN: key_id = Rml::Input::KI_NEXT; break;

                        // Letters A-Z
                        case SDLK_a:        key_id = Rml::Input::KI_A; break;
                        case SDLK_b:        key_id = Rml::Input::KI_B; break;
                        case SDLK_c:        key_id = Rml::Input::KI_C; break;
                        case SDLK_d:        key_id = Rml::Input::KI_D; break;
                        case SDLK_e:        key_id = Rml::Input::KI_E; break;
                        case SDLK_f:        key_id = Rml::Input::KI_F; break;
                        case SDLK_g:        key_id = Rml::Input::KI_G; break;
                        case SDLK_h:        key_id = Rml::Input::KI_H; break;
                        case SDLK_i:        key_id = Rml::Input::KI_I; break;
                        case SDLK_j:        key_id = Rml::Input::KI_J; break;
                        case SDLK_k:        key_id = Rml::Input::KI_K; break;
                        case SDLK_l:        key_id = Rml::Input::KI_L; break;
                        case SDLK_m:        key_id = Rml::Input::KI_M; break;
                        case SDLK_n:        key_id = Rml::Input::KI_N; break;
                        case SDLK_o:        key_id = Rml::Input::KI_O; break;
                        case SDLK_p:        key_id = Rml::Input::KI_P; break;
                        case SDLK_q:        key_id = Rml::Input::KI_Q; break;
                        case SDLK_r:        key_id = Rml::Input::KI_R; break;
                        case SDLK_s:        key_id = Rml::Input::KI_S; break;
                        case SDLK_t:        key_id = Rml::Input::KI_T; break;
                        case SDLK_u:        key_id = Rml::Input::KI_U; break;
                        case SDLK_v:        key_id = Rml::Input::KI_V; break;
                        case SDLK_w:        key_id = Rml::Input::KI_W; break;
                        case SDLK_x:        key_id = Rml::Input::KI_X; break;
                        case SDLK_y:        key_id = Rml::Input::KI_Y; break;
                        case SDLK_z:        key_id = Rml::Input::KI_Z; break;

                        // Numbers 0-9
                        case SDLK_0:        key_id = Rml::Input::KI_0; break;
                        case SDLK_1:        key_id = Rml::Input::KI_1; break;
                        case SDLK_2:        key_id = Rml::Input::KI_2; break;
                        case SDLK_3:        key_id = Rml::Input::KI_3; break;
                        case SDLK_4:        key_id = Rml::Input::KI_4; break;
                        case SDLK_5:        key_id = Rml::Input::KI_5; break;
                        case SDLK_6:        key_id = Rml::Input::KI_6; break;
                        case SDLK_7:        key_id = Rml::Input::KI_7; break;
                        case SDLK_8:        key_id = Rml::Input::KI_8; break;
                        case SDLK_9:        key_id = Rml::Input::KI_9; break;

                        // Numpad
                        case SDLK_KP_0:     key_id = Rml::Input::KI_NUMPAD0; break;
                        case SDLK_KP_1:     key_id = Rml::Input::KI_NUMPAD1; break;
                        case SDLK_KP_2:     key_id = Rml::Input::KI_NUMPAD2; break;
                        case SDLK_KP_3:     key_id = Rml::Input::KI_NUMPAD3; break;
                        case SDLK_KP_4:     key_id = Rml::Input::KI_NUMPAD4; break;
                        case SDLK_KP_5:     key_id = Rml::Input::KI_NUMPAD5; break;
                        case SDLK_KP_6:     key_id = Rml::Input::KI_NUMPAD6; break;
                        case SDLK_KP_7:     key_id = Rml::Input::KI_NUMPAD7; break;
                        case SDLK_KP_8:     key_id = Rml::Input::KI_NUMPAD8; break;
                        case SDLK_KP_9:     key_id = Rml::Input::KI_NUMPAD9; break;
                        case SDLK_KP_ENTER: key_id = Rml::Input::KI_NUMPADENTER; break;
                        case SDLK_KP_MULTIPLY: key_id = Rml::Input::KI_MULTIPLY; break;
                        case SDLK_KP_PLUS:  key_id = Rml::Input::KI_ADD; break;
                        case SDLK_KP_MINUS: key_id = Rml::Input::KI_SUBTRACT; break;
                        case SDLK_KP_PERIOD: key_id = Rml::Input::KI_DECIMAL; break;
                        case SDLK_KP_DIVIDE: key_id = Rml::Input::KI_DIVIDE; break;

                        // Function keys
                        case SDLK_F1:       key_id = Rml::Input::KI_F1; break;
                        case SDLK_F2:       key_id = Rml::Input::KI_F2; break;
                        case SDLK_F3:       key_id = Rml::Input::KI_F3; break;
                        case SDLK_F4:       key_id = Rml::Input::KI_F4; break;
                        case SDLK_F5:       key_id = Rml::Input::KI_F5; break;
                        case SDLK_F6:       key_id = Rml::Input::KI_F6; break;
                        case SDLK_F7:       key_id = Rml::Input::KI_F7; break;
                        case SDLK_F8:       key_id = Rml::Input::KI_F8; break;
                        case SDLK_F9:       key_id = Rml::Input::KI_F9; break;
                        case SDLK_F10:      key_id = Rml::Input::KI_F10; break;
                        case SDLK_F11:      key_id = Rml::Input::KI_F11; break;
                        case SDLK_F12:      key_id = Rml::Input::KI_F12; break;

                        // Punctuation
                        case SDLK_SEMICOLON: key_id = Rml::Input::KI_OEM_1; break;
                        case SDLK_PLUS:     key_id = Rml::Input::KI_OEM_PLUS; break;
                        case SDLK_COMMA:    key_id = Rml::Input::KI_OEM_COMMA; break;
                        case SDLK_MINUS:    key_id = Rml::Input::KI_OEM_MINUS; break;
                        case SDLK_PERIOD:   key_id = Rml::Input::KI_OEM_PERIOD; break;
                        case SDLK_SLASH:    key_id = Rml::Input::KI_OEM_2; break;
                        case SDLK_BACKQUOTE: key_id = Rml::Input::KI_OEM_3; break;
                        case SDLK_LEFTBRACKET: key_id = Rml::Input::KI_OEM_4; break;
                        case SDLK_BACKSLASH: key_id = Rml::Input::KI_OEM_5; break;
                        case SDLK_RIGHTBRACKET: key_id = Rml::Input::KI_OEM_6; break;
                        case SDLK_QUOTE:    key_id = Rml::Input::KI_OEM_7; break;

                        default: break;
                    }

                    // Map modifiers (check for both left and right modifier keys)
                    if (event.key.keysym.mod & (KMOD_LSHIFT | KMOD_RSHIFT))
                        key_modifier |= Rml::Input::KM_SHIFT;
                    if (event.key.keysym.mod & (KMOD_LCTRL | KMOD_RCTRL))
                        key_modifier |= Rml::Input::KM_CTRL;
                    if (event.key.keysym.mod & (KMOD_LALT | KMOD_RALT))
                        key_modifier |= Rml::Input::KM_ALT;

                    if (key_id != Rml::Input::KI_UNKNOWN) {
                        if (event.type == SDL_KEYDOWN) {
                            rml_context_->ProcessKeyDown(key_id, key_modifier);
                        } else {
                            rml_context_->ProcessKeyUp(key_id, key_modifier);
                        }
                    }
                    break;
                }
                case SDL_DROPFILE:
                    // Handle file/folder drag and drop
                    if (event.drop.file) {
                        std::string dropped_path(event.drop.file);
                        SDL_free(event.drop.file);

                        LOG_INFO("Drop detected: {}", dropped_path);

                        // Determine if it's a file or directory
                        PayloadMap payload;
                        payload["path"] = dropped_path;

                        try {
                            if (std::filesystem::is_directory(dropped_path)) {
                                payload["is_directory"] = true;
                                LOG_INFO("Dropped item is a directory");
                            } else {
                                payload["is_directory"] = false;
                                LOG_INFO("Dropped item is a file");
                            }
                        } catch (const std::exception& e) {
                            LOG_WARN("Error checking dropped path '{}': {}", dropped_path, e.what());
                            payload["is_directory"] = false;
                        }

                        // Dispatch file_drop as a global event
                        // Note: A Lua thread must register for this global event to receive it
                        event_dispatcher_->DispatchGlobalEvent("file_drop", payload);
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
                    } else if (lower_path.ends_with(".lua")) {
                        LOG_INFO("Lua file changed: {}, clearing Lua cache and reloading all documents", command.path);
                        document_manager_->HandleLuaFileChanged(normalized_path);
                    }
                }
            } else {
                // Delegate all other commands to CommandProcessor
                command_processor_->ProcessCommand(cmd);
            }
        }
    }

    void Update() {
        // Cleanup expired notifications (once per frame is plenty)
        NotificationOverlay::CleanupExpired();

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

    // Custom element instancers (must outlive RmlUi context)
    std::unique_ptr<Rml::ElementInstancerGeneric<ElementCanvas>> canvas_instancer_;
    std::unique_ptr<ElementTextEditorInstancer> texteditor_instancer_;

    std::unique_ptr<moodycamel::ConcurrentQueue<Command>> command_queue_;
    std::unique_ptr<EventDispatcher> event_dispatcher_;
    std::unique_ptr<DataStore> data_store_;
    std::unique_ptr<ThreadManager> thread_manager_;
    std::unique_ptr<RmlUiBridge> rmlui_bridge_;

    // Managers
    std::unique_ptr<DocumentManager> document_manager_;
    std::unique_ptr<DataModelManager> data_model_manager_;
    std::unique_ptr<CommandProcessor> command_processor_;
    std::unique_ptr<NotificationFeed> notification_feed_;
    Rml::DataModelHandle notif_model_handle_;
    int notification_count_ = 0;  // Count for data binding

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
