---
target: project design system
total_score: 24
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 2
timestamp: 2026-09-04T23-05-00Z
slug: lib-eye-in-the-sky-web
---
Method: dual-agent (A: /root/design_review · B: /root/implementation_evidence)

EITS has a convincing visual identity, but an uneven design-system contract. Preserve the calm operator-console direction and make status, readability, and shared component behavior dependable. This bounded review covered DESIGN.md, PRODUCT.md, CSS, shared components, and desktop browser views of Sessions, Jobs, Components, and IAM Simulator. It is not a complete accessibility or workflow certification.

The product feels authored for agent supervision: restrained tonal surfaces, compact rows, technical metadata, persistent navigation, search, selection and command-palette shortcuts fit its users. The overview still behaves more like a session archive than a control room: it is easier to see history than identify what needs intervention.

| Heuristic | Score / 4 | Main finding |
|---|---:|---|
| Visibility of system status | 2 | Important distinctions are dots or absent visually. |
| Match with real-world concepts | 3 | Developer vocabulary fits; Agent/Session naming diverges. |
| User control and freedom | 3 | Selection, cancellation and navigation exist. |
| Consistency and standards | 2 | Control dimensions, status colors and page context diverge. |
| Error prevention | 3 | Confirmations exist; destructive flows were not executed. |
| Recognition over recall | 2 | Icon navigation and implicit state require learned context. |
| Flexibility and efficiency | 3 | Search, shortcuts, sorting and bulk selection support experts. |
| Aesthetic and minimalist design | 3 | Calm composition; operational metadata is too subdued. |
| Error recovery | 1 | Internal/generic error language lacks recovery guidance. |
| Help and documentation | 2 | Tooltips exist; component examples contradict implementation. |
| Total | 24/40 | Acceptable foundation; significant consistency work remains. |

Strengths: coherent flat surface hierarchy; real expert accelerators; intentional accessibility foundations including a skip link, accessible session status names, and reduced-motion CSS. Preserve these.

1. [P1] Make status a shared operational language. Session rows intentionally leave idle, stale idle, dead idle and completed visually blank (components/session_card.ex:111). Shared running/working dots are green (components/core_components.ex:1244), jobs running is blue (components/jobs_page.ex:430), and the component demo shows working in amber (live/components_live.html.heex:85). Users must reinterpret state across modules. Define state labels, icons, colors, urgency and next actions centrally, with documented entity-specific exceptions. Include an attention view/count. A status should remain understandable without color. Suggested command: impeccable clarify.

2. [P1] Separate density from faintness. Session model/time metadata uses 11px text at 30% foreground opacity (components/session_card.ex:153). These are essential disambiguators among generic New Chat titles. The system defines 9–13px tiers (assets/css/app.css:24), while the library advertises a 17px DM Sans body (live/components_live.html.heex:156). Define essential/secondary/decorative text roles and verify essential metadata across themes. Keep compact rows; reserve extreme muting for decoration. No contrast ratios were measured in this critique. Suggested commands: impeccable typeset and audit.

3. [P2] Turn the style vocabulary into a reliable component contract. DESIGN.md:78 specifies 28px primary controls; CSS defaults to 36px actions and 44px icon buttons (assets/css/app.css:133,235); demo examples override these again (live/components_live.html.heex:39). The shared button exposes only primary/default variants and custom classes replace defaults (components/core_components.ex:153). IAM Simulator visibly mixes narrow raw controls, inconsistent label placement and an action below the initial 1280x720 viewport (live/iam_live/simulator.ex:249). Define named density/size/intent variants, use shared form layout primitives, and render demo examples from production components. Compatibility class names alone do not prove a defect; document approved aliases and eliminate behavioral drift. Suggested commands: impeccable document and harden.

4. [P2] Clarify action and navigation context. Sessions presents New Session and New Agent for the same drawer event (live/agent_live/index.ex:34,232). Components appears beneath a Sessions toolbar because sidebar_tab defaults to sessions (components/layouts/app.html.heex:175). The rail has 16 destinations (components/rail.ex:646); persisted Files/Notes flyouts can coexist with unrelated page context. Use one creation term and one dominant action, assign route-specific chrome, group navigation by operator work, and clearly identify independently pinned side panels. Persistence itself may be intentional. Suggested commands: impeccable distill and layout.

5. [P2] Define recovery and reassurance as system patterns. Jobs displayed Unknown event: set_notify_on_stop during inspection; its trigger/root cause was not established. Session actions contain generic/raw errors (live/agent_live/index_actions.ex:59,204,331). Library examples include Something went wrong (live/components_live.html.heex:310). Define operation + problem + next step, preserve user input, and disclose technical detail separately. IAM Simulator's explicit dry-run/no-state-written explanation is a positive model for reassurance. Suggested command: impeccable harden.

Cognitive load: the overview review found four heuristic checklist failures: single focus, chunking, visual hierarchy and minimal choices. Sixteen navigation destinations are one concrete large choice set; this is not a rule limiting data lists to four rows. Grouping and progressive disclosure provide a good base.

Emotional journey: arrival feels calm and credible; monitoring becomes effortful when state and faint metadata require reconstruction; completion is weakly distinguished from idle. Make intervention and outcome legible without adding decoration.

Persona red flags: power users lack an obvious attention-first route; low-vision operators face faint essential metadata despite accessible row status names; newcomers must infer Agent versus Session and the scope of persistent flyouts.

Minor observations: browser titles still include Phoenix Framework; loading/empty-state timing and hidden drawer accessibility merit targeted checks but were not established as bugs. Icon examples should follow the existing robot/message/document semantic decisions.

Automated evidence: detector returned zero findings because it scanned zero supported files in the 311-file Phoenix target. HEEx/Elixir are unsupported by its extension list. This is a coverage gap, not a clean bill of health. Browser/source review supplies the findings; no detector false positives exist.

Questions for the next pass: What should an operator know within five seconds? Which issue should be addressed first? How broad should the implementation pass be?
