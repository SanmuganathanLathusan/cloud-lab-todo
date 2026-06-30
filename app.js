const express = require("express");
const Database = require("better-sqlite3");

const app = express();
const db = new Database("todos.db");

app.use(express.json());

db.prepare(`
CREATE TABLE IF NOT EXISTS todos(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task TEXT,
    completed INTEGER DEFAULT 0
)
`).run();

app.get("/", (req, res) => {
    res.send("Cloud Lab Week 08 Todo API Running");
});

app.get("/api/todos", (req, res) => {
    const todos = db.prepare("SELECT * FROM todos").all();
    res.json(todos);
});

app.post("/api/todos", (req, res) => {

    const { task } = req.body;

    db.prepare(
        "INSERT INTO todos(task) VALUES(?)"
    ).run(task);

    res.json({
        message: "Todo Added"
    });

});

app.listen(3000, () => {
    console.log("Server running on port 3000");
});
