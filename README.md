# Setting Up and Using Python Virtual Environment (venv)

## Prerequisites

Ensure you have the following installed on your system:

- **Python** (version 3.3 or higher)
  ```bash
  python --version
  ```
- **pip** (Python package manager)
  ```bash
  pip --version
  ```

## Creating a Virtual Environment

Navigate to your project directory (or create one) and run:

- **On Linux/macOS:**
  ```bash
  python3 -m venv env
  ```
- **On Windows:**
  ```bash
  python -m venv env
  ```

This will create a new directory `env`, containing the virtual environment.

## Activating the Virtual Environment

- **On Linux/macOS:**
  ```bash
  source env/bin/activate
  ```
- **On Windows:**
  ```bash
  env\Scripts\activate
  ```

Once activated, your terminal prompt should show the environment name `(env)`.

## Installing Packages from `requirements.txt`

Ensure the `requirements.txt` file is present in the project directory and run:

```bash
pip install -r requirements.txt
```

This installs all the necessary dependencies specified in `requirements.txt`.

## Running `nextcloud-cli.py`

To execute `nextcloud-cli.py` within the virtual environment, ensure the environment is activated and then run:

```bash
python nextcloud-cli.py
```

## Working Inside the Virtual Environment

- **To use Python within the virtual environment:** Run your Python scripts as usual.
- **To exit the virtual environment:**
  ```bash
  deactivate
  ```

## Notes
- Using a virtual environment ensures project dependencies remain isolated.
- Always activate the virtual environment before running Python commands in your project.
- If `pip` is outdated, upgrade it within the virtual environment:
  ```bash
  pip install --upgrade pip
  ```
