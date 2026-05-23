# PlantUML Diagrams

Standalone `.puml` source files for Aroll+. Same content as embedded diagrams in the markdown docs.

## Folders

| Folder | Source doc | Files |
|--------|------------|-------|
| [solution/](solution/) | [SOLUTION.md](../SOLUTION.md) | 7 — architecture, use cases, core sequences |
| [erd/](erd/) | [DATABASE-ERD.md](../DATABASE-ERD.md) | 4 — domains, full ERD, enums, payroll TBD |
| [workflows/](workflows/) | [SYSTEM-WORKFLOWS.md](../SYSTEM-WORKFLOWS.md) | 13 — processes, states, data flow |

**Total: 24 diagrams**

## Preview in Cursor / VS Code

1. Install extension: [PlantUML](https://marketplace.visualstudio.com/items?itemName=jebbs.plantuml)
2. Open any `.puml` file
3. `Alt+D` (or command **PlantUML: Preview Current Diagram**)

Requires [Graphviz](https://graphviz.org/download/) for some diagram types, or use the extension’s built-in PlantUML server.

## Export PNG / SVG (CLI)

If [PlantUML JAR](https://plantuml.com/download) is installed:

```bash
cd docs/diagrams
java -jar plantuml.jar -tpng solution/*.puml erd/*.puml workflows/*.puml
```

Output images appear next to each `.puml` file.

## Online

Copy file contents into [plantuml.com/plantuml](https://www.plantuml.com/plantuml).

## File index

### solution/

| File | Diagram |
|------|---------|
| `01-aroll-context.puml` | System context |
| `02-aroll-container.puml` | Containers |
| `03-aroll-erd-core.puml` | Core ERD (summary) |
| `04-aroll-use-case.puml` | Use cases |
| `05-onboarding-sequence.puml` | Business onboarding |
| `06-clock-in-sequence.puml` | Clock-in sequence |
| `07-payroll-sequence.puml` | Payroll sequence |

### erd/

| File | Diagram |
|------|---------|
| `01-erd-domains.puml` | Data domains |
| `02-erd-full.puml` | Full ERD with columns |
| `03-erd-enums.puml` | Enumeration types |
| `04-erd-payroll-tbd.puml` | Payroll rules (TBD W1) |

### workflows/

| File | Diagram |
|------|---------|
| `01-system-overview.puml` | System overview |
| `02-request-flow.puml` | HTTP request flow |
| `03-business-state.puml` | Business lifecycle |
| `04-employee-journey.puml` | Employee journey |
| `05-face-enrollment.puml` | Face enrollment |
| `06-clock-workflow.puml` | Clock-in activity |
| `07-attendance-state.puml` | Attendance states |
| `08-shift-workflow.puml` | Shift assignment |
| `09-payroll-activity.puml` | Payroll activity |
| `10-payroll-state.puml` | Payroll run states |
| `11-rbac-flow.puml` | Login / RBAC |
| `12-data-flow.puml` | Attendance → payroll |
| `13-error-flow.puml` | Clock-in errors |
