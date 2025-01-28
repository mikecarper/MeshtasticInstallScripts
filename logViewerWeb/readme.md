Copy contents into `/opt/logViewerWeb`.
```
sudo mkdir /opt/logViewerWeb
sudo chmod 777 /opt/logViewerWeb
cd /opt/logViewerWeb
```

Start node.js project.
```
npm init -y
npm install express ws chokidar
```

Create a service.
```
sudo nano /etc/systemd/system/mesh-logger.service
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
sudo systemctl enable mesh-logger
sudo systemctl start mesh-logger
```
