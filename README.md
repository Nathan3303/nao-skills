# nao-skills

Agent skills collection for OpenCode / Sisyphus. Made by [Nathan Lee](https://github.com/nathan).

## Skills

### `nao-frontend-ddd`

Frontend Domain-Driven Design architecture guide based on **Vue 3 + TypeScript / React + TypeScript**. Provides a progressive 3-level DDD framework:

| Level                     | Scope                | Key Patterns                               |
| ------------------------- | -------------------- | ------------------------------------------ |
| **Level 1** — Lightweight | < 5k LOC, 1–2 devs   | Composable-based business logic            |
| **Level 2** — Basic DDD   | 5k–20k LOC, 3–5 devs | Per-domain stores (Pinia/Zustand) + UseCase |
| **Level 3** — Full DDD    | > 20k LOC, monorepo  | Domain / Application / Presentation layers |

When invoked, the skill assesses project size, selects the appropriate DDD level, and provides the minimal structure and code patterns with clear graduation criteria for when to level up.

See [nao-frontend-ddd/SKILL.md](nao-frontend-ddd/SKILL.md) for the full architecture guide, patterns, and migration paths.

### `my-nueui`

Build Vue 3 business components and pages with the **NueUI** component library (~30+ components). Covers the full component catalog with progressive building levels:

| Level       | Scope                               | Deliverable                                   |
| ----------- | ----------------------------------- | --------------------------------------------- |
| **Level 0** | Single component                    | One `<nue-*>` tag with correct props          |
| **Level 1** | Simple composition (2–3 components) | Small UI fragment                             |
| **Level 2** | Form building                       | Login, settings, filter forms                 |
| **Level 3** | Layout composition                  | Admin panels, card grids, multi-section pages |
| **Level 4** | Overlay composition                 | Modals, drawers, tooltips, dropdowns          |
| **Level 5** | Full business components            | Complete features with all states             |

Includes theming, dark mode (single CSS variable toggle), iconfont, and design token usage.

See [my-nueui/SKILL.md](my-nueui/SKILL.md) for the full guide, component catalog, and business recipes.

## Project Structure

```text
nao-skills/
├── nao-frontend-ddd/       # Frontend DDD architecture skill
│   └── SKILL.md            # Main skill definition
├── my-nueui/               # NueUI component library skill
│   ├── SKILL.md            # Main skill definition
│   └── reference/          # Component & API reference docs
│       ├── components-*.md
│       ├── recipes.md
│       ├── programmatic-api.md
│       ├── theme-packages.md
│       └── ...
└── package.json
```

## License

MIT © 2026 Nathan Lee
