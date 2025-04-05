# DeepDoc Client Action

![GitHub release (latest by date)](https://img.shields.io/github/v/release/TrueSelph/deepdoc_client_action)
![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/TrueSelph/deepdoc_client_action/test-intro_interact_action.yaml)
![GitHub issues](https://img.shields.io/github/issues/TrueSelph/deepdoc_client_action)
![GitHub pull requests](https://img.shields.io/github/issues-pr/TrueSelph/deepdoc_client_action)
![GitHub](https://img.shields.io/github/license/TrueSelph/deepdoc_client_action)

The **DeepDoc Client Action** interfaces with the [DeepDoc](https://github.com/infiniflow/ragflow/blob/main/deepdoc) service for document processing, chunking, and metadata extraction. It allows users to upload documents or document URLs in batches for various formats (PDF, DOCX, Excel, PPT, TXT), facilitating asynchronous document processing and ingestion into a configured vector store.

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

## 📖 Best Practices

- Validate your API keys and model parameters thoroughly before deployment.
- Test pipelines extensively in staging environments before promoting to production.

---

## 🔰 Contributing

- **🐛 [Report Issues](https://github.com/TrueSelph/deepdoc_store_action/issues)**: Submit reports for bugs identified or feature requests.
- **💡 [Submit Pull Requests](https://github.com/TrueSelph/deepdoc_store_action/blob/main/CONTRIBUTING.md)**: Review open PRs and submit your implementations.

<details>
<summary>Contributing Guidelines</summary>

1. **Fork** the repository using GitHub’s fork button.
2. **Clone** your fork locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/deepdoc_store_action
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
    <a href="https://github.com/TrueSelph/deepdoc_store_action/graphs/contributors">
        <img src="https://contrib.rocks/image?repo=TrueSelph/deepdoc_store_action" />
   </a>
</p>
</details>

---

## 🎗 License

This project is licensed under the **Apache License 2.0**. See the [LICENSE](../LICENSE) file for additional licensing information.

---