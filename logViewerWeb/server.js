const express = require("express");
const http = require("http");
const WebSocket = require("ws");
const chokidar = require("chokidar");
const fs = require("fs");
const path = require("path");

////////////////////////////////////////////////////////////////////////////////
// CONFIGURATION
////////////////////////////////////////////////////////////////////////////////
const LOGS_DIR = "/opt/meshing-around/logs"; // Directory where your log files live
const PORT = 3000;                           // Port to run the web server

////////////////////////////////////////////////////////////////////////////////
// GLOBALS
////////////////////////////////////////////////////////////////////////////////
// We'll keep track of watchers and their subscribers so we only watch each file once.
const watchers = {}; 
// watchers = {
//   "meshbot.log": {
//       watcher: <chokidar watcher>,
//       clients: Set of WebSocket clients
//   },
//   "meshbot.log.2025-01-27": { ... },
//   ...
// }

////////////////////////////////////////////////////////////////////////////////
// EXPRESS + SERVER SETUP
////////////////////////////////////////////////////////////////////////////////
const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

// 1. API endpoint to list files in LOGS_DIR
app.get("/api/files", (req, res) => {
  fs.readdir(LOGS_DIR, (err, files) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    // You might filter out anything not matching *.log* if you wish:
    // files = files.filter(file => file.startsWith('meshbot.log') || file.startsWith('messages.log'));
    res.json({ files });
  });
});

// 2. Serve static files (our frontend) from 'public' folder
app.use(express.static(path.join(__dirname, "public")));

// 3. Handle WebSocket connections for real-time log updates
wss.on("connection", (ws) => {
  console.log("New client connected via WebSocket.");
  let currentFile = null;  // track which file this client is subscribed to

  // The client will send a JSON message like: { action: "subscribe", file: "filename" }
  ws.on("message", (msg) => {
    try {
      const data = JSON.parse(msg);
      if (data.action === "subscribe") {
        const fileName = data.file;
        if (fileName) {
          // Unsubscribe from the previous file if any
          if (currentFile) {
            unsubscribeFromFile(ws, currentFile);
          }
          subscribeToFile(ws, fileName);
          currentFile = fileName;
        }
      }
    } catch (err) {
      console.error("Error parsing WebSocket message:", err);
    }
  });

  // Cleanup when client disconnects
  ws.on("close", () => {
    console.log("Client disconnected");
    if (currentFile) {
      unsubscribeFromFile(ws, currentFile);
    }
  });
});

////////////////////////////////////////////////////////////////////////////////
// HELPER FUNCTIONS
////////////////////////////////////////////////////////////////////////////////
/**
 * Subscribe this WebSocket client to a given file.
 * If no watcher exists yet for that file, create it.
 */
function subscribeToFile(ws, fileName) {
  const fullPath = path.join(LOGS_DIR, fileName);

  // If we don't already have a watcher for this file, create one
  if (!watchers[fileName]) {
    watchers[fileName] = {
      watcher: chokidar.watch(fullPath),
      clients: new Set()
    };

    // Whenever the file changes, read it and broadcast to subscribed clients
    watchers[fileName].watcher.on("change", () => {
      broadcastFile(fileName);
    });
  }

  // Add this client to the set
  watchers[fileName].clients.add(ws);

  // Send the current file contents immediately
  fs.readFile(fullPath, "utf8", (err, data) => {
    if (err) {
      console.error("Error reading file:", err);
      ws.send(JSON.stringify({ file: fileName, content: `Error reading file: ${err.message}` }));
    } else {
      ws.send(JSON.stringify({ file: fileName, content: data }));
    }
  });
}

/**
 * Unsubscribe a client from a specific file and remove the watcher if no clients remain.
 */
function unsubscribeFromFile(ws, fileName) {
  const entry = watchers[fileName];
  if (!entry) return;

  entry.clients.delete(ws);

  // If no more clients are watching this file, close the watcher & remove it
  if (entry.clients.size === 0) {
    entry.watcher.close();
    delete watchers[fileName];
  }
}

/**
 * Read and broadcast the file contents to all WebSocket clients subscribed to it.
 */
function broadcastFile(fileName) {
  const entry = watchers[fileName];
  if (!entry) return;

  const fullPath = path.join(LOGS_DIR, fileName);
  fs.readFile(fullPath, "utf8", (err, data) => {
    if (err) {
      console.error("Error reading file:", err);
      return;
    }

    // Send the updated content to each client
    for (const client of entry.clients) {
      if (client.readyState === WebSocket.OPEN) {
        client.send(JSON.stringify({ file: fileName, content: data }));
      }
    }
  });
}

////////////////////////////////////////////////////////////////////////////////
// START THE SERVER
////////////////////////////////////////////////////////////////////////////////
server.listen(PORT, () => {
  console.log(`Log viewer is running on http://localhost:${PORT}`);
});
