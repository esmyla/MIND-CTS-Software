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

    %% --- START ---
    A([START]) --> B[Initialize finger-tracking<br/>+ grip sensor modules]

    %% --- HAND DETECTION ---
    B --> C{Is hand detected?}
    C -- NO --> C
    C -- YES --> D[Check READY position<br/>(neutral hand, baseline force)]

    %% --- READY STATE ---
    D --> E{Is READY state?}
    E -- NO --> D
    E -- YES --> F[Reset buffers<br/>Wait for user to begin gripping]

    %% --- START DETECTION ---
    F --> G{Flexion > MIN_FLEX_ANGLE<br/>OR Force > MIN_FORCE_THRESHOLD?}
    G -- NO --> F
    G -- YES --> H[Mark START time<br/>Begin recording sensor + tracking data]

    %% --- ACTIVE PHASE ---
    H --> I{Grip still active?<br/>(force or flexion above threshold)}
    I -- YES --> H
    I -- NO --> J[Begin relaxation check]

    %% --- END DETECTION ---
    J --> K{Relaxed for<br/>STILLNESS_FRAMES?}
    K -- NO --> H
    K -- YES --> L[Mark END time<br/>Stop recording]

    %% --- STORE METRICS ---
    L --> M[Compute metrics:<br/>peak force, duration, etc.]
    M --> N[Store to database<br/>(existing pipeline)]

    %% --- COMPLETE ---
    N --> O{Start another set?}
    O -- YES --> D
    O -- NO --> P([END])
