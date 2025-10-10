# **Manufold Client**

## **Overview**

**Manufold Client** is a desktop application that transforms unstructured data into structured, queryable knowledge environments. It serves as the entry point for creating new *leaves* within the Manufold ecosystem.

The client guides users through an agent-assisted workflow that:
1. **Ingests** arbitrary files and folders
2. **Understands** the data's structure and meaning through exploration
3. **Proposes** a tailored data model that captures the essence of the information
4. **Transforms** raw files into a structured database
5. **Visualizes** the imported data through a purpose-built interface

Each session creates a self-contained environment where the agent learns the user's domain, validates its understanding, and generates all necessary infrastructure — from database schemas to parsing scripts to visualization interfaces.

---

## **Workflow**

### **1. Environment Creation**
Users drag and drop files and folders into the client, creating an isolated workspace. The client accepts any file format — spreadsheets, CSVs, JSON, text documents, images with metadata, PDFs, or nested directory structures.

The environment acts as a sandbox where the agent can safely explore without affecting external systems.

### **2. Agent Exploration**
The agent systematically examines the ingested data:
- Reads file contents and metadata
- Identifies patterns, relationships, and hierarchies
- Recognizes domain-specific terminology and concepts
- Detects data types, formats, and structural conventions

This phase is iterative — the agent may request clarification or additional context from the user as it builds its understanding.

### **3. Understanding Validation**
The agent presents a **comprehension document** that articulates:
- What the data represents (domain, purpose, scope)
- Key entities and their attributes
- Relationships between data elements
- Temporal, spatial, or hierarchical structures
- Anomalies, gaps, or ambiguities discovered

The user reviews this document and provides feedback. If the understanding is incomplete or incorrect, the agent refines its analysis. This cycle continues until the user confirms the agent has accurately captured the data's meaning.

### **4. Data Model Proposal**
Once understanding is validated, the agent designs a **data model** that:
- Reflects the natural structure of the domain
- Normalizes where appropriate while preserving semantic relationships
- Accommodates the specific patterns found in the user's data
- Supports the queries and views the community will need

The proposed model is presented with visual schema diagrams and explanatory notes. The user can request revisions before proceeding.

### **5. Data Transformation**
With an approved data model, the agent:
- Generates parsing scripts for each file type encountered
- Handles format conversions, data cleaning, and validation
- Maps source data to the target schema
- Executes the import process with progress tracking
- Reports any errors or data quality issues

All generated scripts are saved and can be reused for future imports or shared with the community.

### **6. View Generation**
Finally, the agent creates an **overview interface** that:
- Presents the most salient aspects of the imported data
- Uses visualizations appropriate to the domain (maps, timelines, graphs, galleries)
- Enables filtering, searching, and basic exploration
- Serves as the starting point for users entering the leaf

This view is not meant to be comprehensive — it's a **portal** into the data, designed to convey the shape and character of the environment at a glance.

---

## **Technical Considerations**

### **Architecture**
- **Desktop application**: We're using c++ rmlui and lua where the application logic lives in lua.
- **Agent runtime**: Claude API (or claude code sdk) with tool-calling capabilities for file reading, analysis, and code generation
- **Database**: SQLite for portability and simplicity, with schema stored alongside the environment
- **Generated artifacts**: All scripts, schemas, and views are human-readable and version-controllable
- **Export**: Export provides the presentation (including sqlite stored data) and excludes the raw data.

### **Agent Capabilities**
The agent is also created in lua.

The agent requires tools for:
- File system traversal and reading
- Structured output generation (comprehension docs, schemas, code)
- Database schema creation and modification
- Data import execution and validation
- Basic visualization generation (RML/RCSS and lua scripts)
- Created in lua with the c++ and lua bridge providing the agent its functionality

### **User Experience**
- **Progressive disclosure**: Simple drag-and-drop start; complexity revealed only as needed
- **Transparency**: Every agent decision is explainable; all generated code is visible
- **Iterative refinement**: Users can backtrack to any stage and revise
- **Portability**: The entire environment — data, schema, views, scripts — can be packaged and shared

**Manufold Client** is the *authoring tool* for Manufold leaves — where raw information becomes a structured world, and where the specific logic of a community's practice takes computational form.