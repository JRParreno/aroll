# Aroll+ Documentation

Design documentation for the thesis **System Design** chapter and implementation reference.

## Documents

| File | Use for |
|------|---------|
| [SOLUTION.md](SOLUTION.md) | Chapter 3 overview — architecture, RBAC, stack, 7 core diagrams |
| [DATABASE-ERD.md](DATABASE-ERD.md) | Database design — full ERD, tables, enums, SQL notes |
| [SYSTEM-WORKFLOWS.md](SYSTEM-WORKFLOWS.md) | Process design — 13 workflow diagrams (clock-in, payroll, states) |

## Getting started

- **[PROJECT-SETUP.md](PROJECT-SETUP.md)** — first-time install (prerequisites, env files, `scripts/setup.ps1`)

## Suggested reading order

1. **SOLUTION.md** — start here for the big picture  
2. **DATABASE-ERD.md** — when writing data requirements or building migrations  
3. **SYSTEM-WORKFLOWS.md** — when explaining how users interact with the system  

## PlantUML

All three files embed PlantUML. **Standalone sources:** [`diagrams/`](diagrams/) — 24 `.puml` files in `solution/`, `erd/`, and `workflows/`.

Install a PlantUML preview extension or use the [online server](https://www.plantuml.com/plantuml) to export figures for your thesis PDF.

## Back to project root

See the main [README.md](../README.md) for project summary, tech stack, and timeline.
