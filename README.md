- clone repo
```
git clone https://github.com/estuart/toughbook_demo_webapp
```
 - install dependencies
```
dnf install ansible git nginx python3-pip
```
Create a virtualenv in the project root and then install needed python requirements
```
pip3 install virtualenv
python3 -m venv venv
source venv/bin/activate
pip3 install -r requirements.txt
```
Configure the firewall to allow web server traffic
```
sudo firewall-cmd --zone=public --add-service=http --permanent
sudo systemctl restart firewalld
```

Copy `config/workload-selector.service` file to `/etc/systemd/system/` and edit file to reflect the proper paths
Copy 'config/flask_app.conf` file to `/etc/nginx/conf.d/`

Now we enable the various services
```
systemctl daemon-reload
systemctl start nginx
systemctl enable nginx
systemctl start workload-selector
systemctl enable workload-selector
```

Debug
You might need to disable selinux with `setenforce 0`
