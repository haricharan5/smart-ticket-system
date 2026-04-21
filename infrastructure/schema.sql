-- Smart Support Ticket System — Azure SQL Schema

CREATE TABLE teams (
    id INT PRIMARY KEY IDENTITY(1,1),
    name NVARCHAR(100) NOT NULL,
    category NVARCHAR(50) NOT NULL
);

CREATE TABLE tickets (
    id INT PRIMARY KEY IDENTITY(1,1),
    title NVARCHAR(500) NOT NULL,
    description NVARCHAR(MAX) NOT NULL,
    submitter_email NVARCHAR(255) NOT NULL,
    category NVARCHAR(50),
    sentiment NVARCHAR(20),
    urgency NVARCHAR(20),
    status NVARCHAR(20) DEFAULT 'open',
    team_id INT FOREIGN KEY REFERENCES teams(id),
    ai_draft_reply NVARCHAR(MAX),
    created_at DATETIME2 DEFAULT GETUTCDATE(),
    sla_deadline DATETIME2,
    resolved_at DATETIME2 NULL
);

CREATE TABLE sla_alerts (
    id INT PRIMARY KEY IDENTITY(1,1),
    ticket_id INT FOREIGN KEY REFERENCES tickets(id),
    alert_type NVARCHAR(50),
    fired_at DATETIME2 DEFAULT GETUTCDATE()
);

CREATE TABLE outage_flags (
    id INT PRIMARY KEY IDENTITY(1,1),
    category NVARCHAR(50) NOT NULL,
    ticket_count INT NOT NULL,
    window_start DATETIME2 NOT NULL,
    window_end DATETIME2 NOT NULL,
    flagged_at DATETIME2 DEFAULT GETUTCDATE(),
    resolved BIT DEFAULT 0
);

INSERT INTO teams (name, category) VALUES
('Technical Support Team', 'Technical Issue'),
('Billing & Finance Team', 'Billing Query'),
('Customer Success Team', 'General Inquiry'),
('HR & People Team', 'HR/Internal'),
('General Operations Team', 'Other');
