# DeepDoc Client Action

![GitHub release (latest by date)](https://img.shields.io/github/v/release/TrueSelph/deepdoc_client_action)
![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/TrueSelph/deepdoc_client_action/test-intro_interact_action.yaml)
![GitHub issues](https://img.shields.io/github/issues/TrueSelph/deepdoc_client_action)
![GitHub pull requests](https://img.shields.io/github/issues-pr/TrueSelph/deepdoc_client_action)
![GitHub](https://img.shields.io/github/license/TrueSelph/deepdoc_client_action)

The **DeepDoc Client Action** interfaces with the JIVAS [DeepDoc](https://github.com/infiniflow/ragflow/blob/main/deepdoc) service for document processing, chunking, metadata extraction, document handling, serving, and integrated management. Users can upload documents or URLs in batches across multiple formats, including PDF, DOCX, Excel, PPT, and TXT. Processing occurs asynchronously, culminating in ingestion and indexing within your configured vector store.

## Document Handling & Management

The **DeepDoc Client Action** now provides comprehensive document handling and management capabilities through built-in file serving integrated with your configured vector store:

- **File Serving and Integration**:
  Uploaded documents can be served directly and are linked seamlessly to stored content within the vector store. When deleting a processed document through this interface, all associated references and indexed vector content will also be automatically removed, maintaining data integrity.

- **Document Management Interface**:
  Users have access to an intuitive management interface to easily view a comprehensive list of all ingested documents. Documents may be quickly added or removed, thereby making repository management straightforward and efficient.

- **Duplicate Prevention Safeguards**:
  Duplicate processing of documents is automatically prevented. The system verifies and ensures that each uploaded document is unique within the repository and vector store, eliminating redundancy and potential confusion.

This package is defined as a singleton action, requiring the Jivas library (version **2.0.0 or higher**) and a properly configured `vector_store_action`. It also requires the Jivas-modified DeepDoc service.

## Package Information

- **Name:** `jivas/deepdoc_client_action`
- **Author:** [V75 Inc.](https://v75inc.com/)
- **Architype:** `DeepDocStoreAction`

## Meta Information

- **Title:** DeepDoc Store Action
- **Group:** core
- **Type:** action

## Configuration

- **Singleton:** true

## Dependencies

- **Jivas:** `^2.0.0`

---

## How to Configure

This action supports configuration either via **environment variables** or directly from within the **action application settings**.

### Configuration Options

| Variable Name              | Description                                    | Default Value                             | Required |
|----------------------------|------------------------------------------------|-------------------------------------------|----------|
| `DEEPDOC_API_URL`          | API endpoint URL of your DeepDoc service       | `http://localhost:8001`           | Yes      |
| `DEEPDOC_API_KEY`          | Your DeepDoc API authentication token          | `api-key` *(replace with secure value)*   | Yes      |
| `JIVAS_BASE_URL`           | Base URL for your Jivas instance; required for the deepdoc callback to function             | http://localhost:8000                                  | Yes |
| `VECTOR_STORE_ACTION`      | Action used for storing vector data            | `TypesenseVectorStoreAction`              | Yes      |

### Option 1: Using Environment Variables

You can configure these values as environment variables so they are accessible to your runtime environment.

#### Linux/MacOS (`.bashrc` or shell configuration):
```bash
export DEEPDOC_API_URL="https://your-custom-deepdoc-url.com"
export DEEPDOC_API_KEY="your-secure-api-key"
export JIVAS_BASE_URL="https://your-jivas-base-url.com"
```

#### Docker (`docker-compose.yml`):
```yaml
environment:
  DEEPDOC_API_URL: "https://your-custom-deepdoc-url.com"
  DEEPDOC_API_KEY: "your-secure-api-key"
  JIVAS_BASE_URL: "https://your-jivas-base-url.com"
```

### Option 2: Using the Action App’s Config

Alternatively, you can configure these variables within the **action app's settings interface** in the JIVAS manager. This is useful if you prefer not to use environment variables or want easy adjustments through the GUI.

From within the action's configuration page:

1. Navigate to your **JIVAS Manangr Dashboard**.
2. Find and select **DeepDoc Client Action** under Actions.
3. Enter the required configuration values (such as `api_url`, `api_key`, and `vector_store_action`) into their respective configuration fields.
4. Save the configuration once complete.

_**Note:** Configuration values set directly within the action app override those provided via environment variables._

After adjusting settings, restart your service or action to apply your changes.

---

### Required Configuration for Local File Serving

If operating locally, you must ensure proper configuration of either local or Amazon S3 file serving to enable this functionality. Configure the following variables in your `.env` file:

```bash
# Set Environment
JIVAS_ENVIRONMENT=development

# JIVAS File Serving Config (Local)
JIVAS_FILE_INTERFACE="local"
JIVAS_FILES_ROOT_PATH=".files"
JIVAS_FILES_URL="http://127.0.0.1:9000/files"

# Alternative: Amazon S3 Configuration
JIVAS_FILE_INTERFACE="s3"
JIVAS_S3_ENDPOINT="your-s3-endpoint"            # optional, typically for custom endpoints
JIVAS_S3_ACCESS_KEY_ID="your-access-key-id"
JIVAS_S3_SECRET_ACCESS_KEY="your-secret-access-key"
JIVAS_S3_REGION="us-east-1"
JIVAS_S3_BUCKET_NAME="your-bucket-name"
```

In addition, running locally requires configuration of MongoDB and a suitable vector store (we strongly recommend Typesense). Include the following configuration in your `.env` file:

```bash
# MongoDB Config
DATABASE_HOST="mongodb://localhost:27017/?replicaSet=my-rs"

# Typesense Vector Store Config
TYPESENSE_HOST="localhost"
TYPESENSE_PORT=8108
TYPESENSE_PROTOCOL="http"
TYPESENSE_API_KEY="abcd"
TYPESENSE_CONNECTION_TIMEOUT_SECONDS=2
```

---

## 📖 Best Practices

- Validate your API keys and model parameters thoroughly before deployment.
- Test pipelines extensively in staging environments before promoting to production.

---

## 🔰 Contributing

- **🐛 [Report Issues](https://github.com/TrueSelph/deepdoc_client_action/issues)**: Submit reports for bugs identified or feature requests.
- **💡 [Submit Pull Requests](https://github.com/TrueSelph/deepdoc_client_action/blob/main/CONTRIBUTING.md)**: Review open PRs and submit your implementations.

<details>
<summary>Contributing Guidelines</summary>

1. **Fork** the repository using GitHub’s fork button.
2. **Clone** your fork locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/deepdoc_client_action
   ```
3. **Create** a new descriptive branch:
   ```bash
   git checkout -b feature-xyz
   ```
4. **Implement** your changes and ensure testing.
5. **Commit** your changes clearly describing updates:
   ```bash
   git commit -m 'feat: add XYZ feature'
   ```
6. **Push** changes back to your branch:
   ```bash
   git push origin feature-xyz
   ```
7. **Submit** a pull request detailing your changes clearly for review.

</details>

<details open>
<summary>Contributor Graph</summary>
<br>
<p align="left">
    <a href="https://github.com/TrueSelph/deepdoc_client_action/graphs/contributors">
        <img src="https://contrib.rocks/image?repo=TrueSelph/deepdoc_client_action" />
   </a>
</p>
</details>

---

## 🎗 License

This project is licensed under the **Apache License 2.0**. See the [LICENSE](../LICENSE) file for additional licensing information.

---