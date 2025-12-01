## Grip Strength Exercise – Finger Tracking Integration

**Right now the code assumes:**  
We already know the exercise has started and ended; just read sensor data and save.

---

### Next Task

With finger tracking, you add a new layer that:

- Watches the hand pose / finger angles.
- Decides when the user has started the grip exercise.
- Continues recording while the user is gripping.
- Detects when the user has finished the exercise.
- Then calls your existing logging function to store the grip-strength metrics in the database.

---

## Wait for Hand in View

- Continuously read finger tracking data.
- Decision: “Is a valid hand detected and tracked?”
  - **NO →**
    - Show message: “Place your hand in view.”
    - Stay in this loop.
  - **YES →**
    - Proceed to next step.

---

## Flowchart

```mermaid
flowchart TD

    A([START]) --> B[Initialize finger tracking and grip sensor modules]

    B --> C{Is hand detected?}
    C -- NO --> C
    C -- YES --> D[Check READY position]

    D --> E{Is READY state?}
    E -- NO --> D
    E -- YES --> F[Reset buffers and wait for user grip]

    F --> G{Flexion > threshold OR Force > threshold?}
    G -- NO --> F
    G -- YES --> H[Mark START time and begin recording]

    H --> I{Grip still active?}
    I -- YES --> H
    I -- NO --> J[Begin relaxation check]

    J --> K{Relaxed long enough?}
    K -- NO --> H
    K -- YES --> L[Mark END time and stop recording]

    L --> M[Compute metrics and process data]
    M --> N[Store to database]

    N --> O{Start another set?}
    O -- YES --> D
    O -- NO --> P([END])
