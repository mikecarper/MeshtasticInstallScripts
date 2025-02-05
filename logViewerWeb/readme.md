Make /opt/logViewerWeb folder
```
sudo mkdir /opt/logViewerWeb
sudo chmod 777 /opt/logViewerWeb

```

Copy contents into `/opt/logViewerWeb`
```
cd /opt/logViewerWeb
wget https://raw.githubusercontent.com/mikecarper/MeshtasticInstallScripts/refs/heads/main/logViewerWeb/server.js
sudo mkdir /opt/logViewerWeb/public
sudo chmod 777 /opt/logViewerWeb/public
cd /opt/logViewerWeb/public
wget https://raw.githubusercontent.com/mikecarper/MeshtasticInstallScripts/refs/heads/main/logViewerWeb/public/index.html
```

Start node.js project.
```
cd /opt/logViewerWeb
npm init -y
npm install express ws chokidar
```

Create a service.
```
sudo nano /etc/systemd/system/meshbotlivelogviewer.service
```
Copy this below into the above service file.
```
[Unit]
Description=Mesh Logger Web Service
After=network.target

[Service]
ExecStart=/usr/bin/node /opt/logViewerWeb/server.js
WorkingDirectory=/opt/logViewerWeb
Restart=always
Environment=NODE_ENV=production
# If you run Node as a specific user, uncomment and adjust:
# User=youruser
# Group=yourgroup

[Install]
WantedBy=multi-user.target
```

Enable the service.
```
sudo systemctl daemon-reload
sudo systemctl enable meshbotlivelogviewer
sudo systemctl start meshbotlivelogviewer
sudo systemctl status meshbotlivelogviewer
```
