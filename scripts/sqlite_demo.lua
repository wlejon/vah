-- SQLite Demo
-- Displays an editable table view with database persistence

local database = nil
local contacts = {}

function init_database()
    -- Open/create database
    local db_handle, error = db.open("data/contacts.db")
    if error ~= "" then
        print("Error opening database: " .. error)
        return false
    end

    database = db_handle
    print("Database opened successfully")

    -- Create contacts table if it doesn't exist
    local success, exec_error = database:execute([[
        CREATE TABLE IF NOT EXISTS contacts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            email TEXT NOT NULL,
            phone TEXT,
            company TEXT,
            notes TEXT
        )
    ]])

    if not success then
        print("Error creating table: " .. exec_error)
        return false
    end

    -- Check if we need to add sample data
    local count_result, count_error = database:query("SELECT COUNT(*) as count FROM contacts")
    if count_error ~= "" then
        print("Error checking row count: " .. count_error)
        return false
    end

    if count_result and #count_result > 0 and count_result[1].count == 0 then
        -- Add some sample data
        print("Adding sample contacts...")
        add_contact("Alice Johnson", "alice@example.com", "555-0101", "Acme Corp", "Lead developer")
        add_contact("Bob Smith", "bob@example.com", "555-0102", "Tech Solutions", "Designer")
        add_contact("Carol Davis", "carol@example.com", "555-0103", "StartUp Inc", "Project manager")
    end

    return true
end

function load_contacts()
    if not database then
        return
    end

    local results, error = database:query("SELECT * FROM contacts ORDER BY name")
    if error ~= "" then
        print("Error loading contacts: " .. error)
        return
    end

    contacts = results or {}
    print("Loaded " .. #contacts .. " contacts")

    -- Note: delete is handled by trigger_delete() function registered in RmlUI's Lua state

    -- Bind data to the model (first time creates the model)
    data.bind("contacts", contacts)

    -- Trigger update to refresh the view
    data.update("contacts")
end

function add_contact(name, email, phone, company, notes)
    if not database then
        return false
    end

    -- Escape single quotes for SQL
    local escaped_name = name:gsub("'", "''")
    local escaped_email = email:gsub("'", "''")
    local escaped_phone = (phone or ""):gsub("'", "''")
    local escaped_company = (company or ""):gsub("'", "''")
    local escaped_notes = (notes or ""):gsub("'", "''")

    local sql = string.format([[
        INSERT INTO contacts (name, email, phone, company, notes)
        VALUES ('%s', '%s', '%s', '%s', '%s')
    ]], escaped_name, escaped_email, escaped_phone, escaped_company, escaped_notes)

    local success, error = database:execute(sql)
    if not success then
        print("Error adding contact: " .. error)
        return false
    end

    print("Added contact: " .. name)
    load_contacts()  -- This will re-query and update the data model
    return true
end

function save_contact(contact_id, name, email, phone, company)
    if not database then
        return false
    end

    -- Escape single quotes for SQL
    local escaped_name = name:gsub("'", "''")
    local escaped_email = email:gsub("'", "''")
    local escaped_phone = phone:gsub("'", "''")
    local escaped_company = company:gsub("'", "''")

    local sql = string.format([[
        UPDATE contacts
        SET name = '%s', email = '%s', phone = '%s', company = '%s'
        WHERE id = %d
    ]], escaped_name, escaped_email, escaped_phone, escaped_company, contact_id)

    local success, error = database:execute(sql)

    if not success then
        print("Error updating contact: " .. error)
        return false
    end

    print("Updated contact with id: " .. contact_id)
    load_contacts()  -- This will re-query and update the data model
    return true
end

function delete_contact(contact_id)
    if not database then
        return false
    end

    local sql = string.format("DELETE FROM contacts WHERE id = %d", contact_id)
    local success, error = database:execute(sql)

    if not success then
        print("Error deleting contact: " .. error)
        return false
    end

    print("Deleted contact with id: " .. contact_id)
    load_contacts()  -- This will re-query and update the data model
    return true
end

function add_random_contact()
    local first_names = {"John", "Jane", "Mike", "Sarah", "David", "Emma", "Chris", "Lisa"}
    local last_names = {"Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller"}
    local companies = {"Tech Corp", "Digital Inc", "Cloud Systems", "Data Solutions", "Web Services"}

    local first = first_names[math.random(#first_names)]
    local last = last_names[math.random(#last_names)]
    local name = first .. " " .. last
    local email = string.lower(first .. "." .. last .. "@example.com")
    local phone = string.format("555-%04d", math.random(1000, 9999))
    local company = companies[math.random(#companies)]

    add_contact(name, email, phone, company, "Randomly generated contact")
end

function startup()
    print("SQLite demo started (thread_id: " .. thread_id .. ")")

    -- Seed random number generator
    math.randomseed(os.time())

    -- Initialize database FIRST
    if not init_database() then
        -- Can't show error in UI since we haven't loaded the document yet
        print("ERROR: Failed to initialize database")
        return
    end

    -- Register event handlers
    event.register("add_contact", function(payload)
        add_random_contact()
    end)

    event.register("save_contact", function(payload)
        if payload.id then
            local contact_id = payload.id

            -- Payload contains edited fields from pending_edits in C++
            -- Fall back to current DB values if not edited
            local contact = nil
            for _, c in ipairs(contacts) do
                if c.id == contact_id then
                    contact = c
                    break
                end
            end

            if contact then
                local name = payload.name or contact.name or ""
                local email = payload.email or contact.email or ""
                local phone = payload.phone or contact.phone or ""
                local company = payload.company or contact.company or ""

                print("Saving contact ID: " .. tostring(contact_id))
                print("  name: " .. name)
                print("  email: " .. email)
                print("  phone: " .. phone)
                print("  company: " .. company)

                save_contact(contact_id, name, email, phone, company)
            else
                print("ERROR: Contact ID " .. tostring(contact_id) .. " not found in contacts array")
            end
        else
            print("ERROR: Missing id in save_contact payload")
        end
    end)

    event.register("delete_contact", function(payload)
        if payload.id then
            local contact_id = payload.id
            print("Deleting contact ID: " .. tostring(contact_id))
            delete_contact(contact_id)
        else
            print("ERROR: No id in delete_contact payload")
        end
    end)

    -- Bind data BEFORE loading UI (so data model exists when document loads)
    load_contacts()

    -- Load UI AFTER data is bound
    ui.load_document("ui/sqlite_demo.rml")
end

function update(dt)
    -- Nothing to update continuously
end

function shutdown()
    if database then
        database:close()
    end
    print("SQLite demo shutting down")
end
