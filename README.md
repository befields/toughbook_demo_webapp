---

# Toughbook Demo Web Application

![Flask](https://img.shields.io/badge/Flask-Python-blue)
![Nginx](https://img.shields.io/badge/Nginx-Web%20Server-red)
![Systemd](https://img.shields.io/badge/Systemd-Services-orange)

## Table of Contents

- [Introduction](#introduction)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
  - [1. Clone the Repository](#1-clone-the-repository)
  - [2. Install Dependencies](#2-install-dependencies)
  - [3. Set Up Python Virtual Environment](#3-set-up-python-virtual-environment)
  - [4. Configure the Firewall](#4-configure-the-firewall)
  - [5. Deploy Configuration Files](#5-deploy-configuration-files)
  - [6. Enable and Start Services](#6-enable-and-start-services)
- [Debugging](#debugging)
- [Usage](#usage)
- [Managing Services](#managing-services)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)
- [Additional Resources](#additional-resources)

---

## Introduction

Welcome to the **Toughbook Demo Web Application** repository! This project demonstrates how to deploy a Flask application with an Nginx web server on a Fedora 40 system using systemd services. This web application is used in conjunction with https://github.com/rlucente-se-jboss/flightgear-kiosk-demo and allows users to select which flightgear workload they would like to deploy to their bootc target.

This README was created with the assistance of ChatGPT.
## Features

- **Flask Web Application**: A lightweight Python web framework for building web applications.
- **Nginx Reverse Proxy**: Serves as a reverse proxy to handle client requests and serve static files efficiently.
- **Systemd Integration**: Manages application lifecycle with systemd services for automatic restarts and boot-time initialization.
- **Firewall Configuration**: Ensures secure network traffic management.
- **SELinux Compliance**: Maintains system security with proper SELinux policies.

## Prerequisites

Before you begin, ensure you have the following:

- **Fedora 40 System**: Updated to the latest version.
- **Administrative Privileges**: Ability to execute commands with `sudo`.
- **Basic Knowledge**: Familiarity with command-line operations, Podman, and systemd concepts.
- **Internet Connection**: Required for installing packages and cloning the repository.

## Installation

Follow the steps below to set up the Toughbook Demo Web Application on your Fedora 40 system.

### 1. Clone the Repository

Begin by cloning the project repository to your local machine.

```bash
git clone https://github.com/estuart/toughbook_demo_webapp
cd toughbook_demo_webapp
```

### 2. Install Dependencies

Install the necessary system packages, including Ansible, Git, Nginx, and Python's pip package manager. 

**📌 Note:** Ansible can also be installed via pip.


```bash
sudo dnf install -y ansible git nginx python3-pip
```

### 3. Set Up Python Virtual Environment

Creating a virtual environment isolates your project dependencies and ensures they don't interfere with system-wide packages.

1. **Install `virtualenv`:**

   ```bash
   pip3 install virtualenv
   ```

2. **Create a Virtual Environment:**

   Navigate to the project root directory and create a virtual environment named `venv`.

   ```bash
   python3 -m venv venv
   ```

3. **Activate the Virtual Environment:**

   ```bash
   source venv/bin/activate
   ```

4. **Install Python Requirements:**

   Install the necessary Python packages listed in `requirements.txt`.

   ```bash
   pip3 install -r requirements.txt
   ```

### 4. Configure the Firewall

Ensure that your system's firewall allows HTTP traffic, enabling web server access.

1. **Allow HTTP Service Permanently:**

   ```bash
   sudo firewall-cmd --zone=public --add-service=http --permanent
   ```

2. **Reload the Firewall to Apply Changes:**

   ```bash
   sudo systemctl restart firewalld
   ```

### 5. Deploy Configuration Files

Copy the necessary service and Nginx configuration files to their respective system directories.

1. **Copy `workload-selector.service` to Systemd Directory:**

   ```bash
   sudo cp config/workload-selector.service /etc/systemd/system/
   ```

   **Edit the Service File:**

   Open the service file in your preferred text editor and update the paths to reflect your project structure.

   ```bash
   sudo vim /etc/systemd/system/workload-selector.service
   ```

   *Ensure that all file paths and environment variables within the service file are correctly set.*

2. **Copy `flask_app.conf` to Nginx Configuration Directory:**

   ```bash
   sudo cp config/flask_app.conf /etc/nginx/conf.d/
   ```

   **Verify Nginx Configuration:**

   Ensure that the Nginx configuration points to the correct upstream Flask application.

   ```bash
   sudo nano /etc/nginx/conf.d/flask_app.conf
   ```

   *Example Configuration:*

```nginx
   server {
    listen 80;
    server_name 192.168.8.200;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
        proxy_connect_timeout 300s;
        client_body_timeout 300s;
        keepalive_timeout 300s;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    error_log /var/log/nginx/flask_app_error.log;
    access_log /var/log/nginx/flask_app_access.log;
}
```

Replace `server_name` if target server is using a different IP address

The `proxy_read_timeout`, `proxy_send_timeout`, `proxy_connect_timeout`, `client_body_timeout`, and `keepalive_timeout` are set to 300s in order to give time for the underlying Ansible playbooks to execute without timing out the web server.

### 6. Enable and Start Services

Manage and activate the necessary services to run your application.

1. **Reload systemd to Recognize New Service Files:**

   ```bash
   sudo systemctl daemon-reload
   ```

2. **Start and Enable Nginx Service:**

   ```bash
   sudo systemctl start nginx
   sudo systemctl enable nginx
   ```

3. **Start and Enable Workload Selector Service:**

   ```bash
   sudo systemctl start workload-selector
   sudo systemctl enable workload-selector
   ```

## Debugging

If you encounter issues with your application, particularly related to SELinux, follow these steps to debug and resolve them.

### SELinux Configuration

Running SELinux in enforcing mode can sometimes block necessary operations for your application. Instead of disabling SELinux, adjust the relevant booleans to allow your application to function correctly.

1. **Enable Nginx to Connect to the Network:**

   ```bash
   sudo setsebool -P httpd_can_network_connect on
   ```

2. **Allow Nginx to Serve Content from User Home Directories:**

   ```bash
   sudo setsebool -P httpd_enable_homedirs on
   ```

*These commands modify SELinux policies to permit Nginx to connect to backend services and serve content from user directories without compromising overall system security.*

*Alternatively, if necessary, you can temporarily set SELinux to permissive mode (not recommended for production environments):*

```bash
sudo setenforce 0
```

*Remember to re-enable enforcing mode after debugging:*

```bash
sudo setenforce 1
```

## Usage

Once all services are running, access your Flask application through your web browser.

1. **Open Web Browser:**

   Navigate to `http://your_domain_or_IP/` to view the application.

2. **Verify Application Functionality:**

   You should see the Flask application's homepage named "Worload Selector"

## Managing Services

Efficiently manage your systemd services to control your application's lifecycle.

### Start Services

```bash
sudo systemctl start nginx
sudo systemctl start workload-selector
```

### Stop Services

```bash
sudo systemctl stop nginx
sudo systemctl stop workload-selector
```

### Restart Services

```bash
sudo systemctl restart nginx
sudo systemctl restart workload-selector
```

### Check Service Status

```bash
sudo systemctl status nginx
sudo systemctl status workload-selector
```

*These commands help you monitor and control the state of your web server and application services.*

## Troubleshooting

If your application isn't working as expected, consider the following troubleshooting steps:

### Common Issues

1. **502 Bad Gateway Error:**

   - **Cause:** Nginx cannot communicate with the Flask backend.
   - **Solution:**
     - Ensure the Flask application is running on the expected port (`8000`).
     - Verify firewall rules allow traffic on port `8000`.
     - Check SELinux booleans as outlined in the [Debugging](#debugging) section.
     - Review Nginx and Flask application logs for detailed error messages.

2. **Service Fails to Start:**

   - **Cause:** Misconfigured systemd service files or missing dependencies.
   - **Solution:**
     - Check the status of the service using `systemctl status`.
     - Inspect logs with `journalctl -u service-name`.
     - Ensure all paths and environment variables in service files are correct.

3. **Firewall Blocking Traffic:**

   - **Cause:** Incorrect firewall configuration.
   - **Solution:**
     - Revisit the firewall configuration steps to ensure HTTP service is allowed.
     - Use `sudo firewall-cmd --list-all` to verify active rules.

4. **SELinux Denials:**

   - **Cause:** SELinux policies restricting necessary operations.
   - **Solution:**
     - Adjust SELinux booleans as outlined in the [Debugging](#debugging) section.
     - Use `audit2allow` to create custom policies if necessary.

### Logs Inspection

- **Nginx Logs:**

  ```bash
  sudo tail -f /var/log/nginx/error.log
  sudo tail -f /var/log/nginx/access.log
  ```

- **Workload Selector Logs:**

  ```bash
  sudo journalctl -u workload-selector.service -f
  ```

*Monitoring logs provides insights into application behavior and helps identify the root cause of issues.*


## Contributing

Contributions are welcome! Please follow these steps to contribute to the project:

1. **Fork the Repository:**

   Click the "Fork" button on the repository page to create your own copy.

2. **Clone Your Fork:**

   ```bash
   git clone https://github.com/your_username/toughbook_demo_webapp.git
   cd toughbook_demo_webapp
   ```

3. **Create a Feature Branch:**

   ```bash
   git checkout -b feature/your-feature-name
   ```

4. **Commit Your Changes:**

   ```bash
   git commit -m "Add your descriptive commit message"
   ```

5. **Push to Your Fork:**

   ```bash
   git push origin feature/your-feature-name
   ```

6. **Create a Pull Request:**

   Navigate to the original repository and create a pull request from your feature branch.


## License

This project is licensed under the [MIT License](LICENSE).

## Additional Resources

- **Systemd Service Files:** [https://www.freedesktop.org/software/systemd/man/systemd.service.html](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
- **Nginx Documentation:** [https://nginx.org/en/docs/](https://nginx.org/en/docs/)
- **Flask Deployment:** [https://flask.palletsprojects.com/en/latest/deploying/](https://flask.palletsprojects.com/en/latest/deploying/)
- **Ansible Documentation:** [https://docs.ansible.com/](https://docs.ansible.com/)

---

**If you have any issues installing/configuring let me know!** Feel free to open an issue or contact me (estuart@redhat.com).

---
