# 🪝 Pinch Strength Sensor Module  
**Index–Thumb (IT) & Middle–Thumb (MT)**

This module records **pinch strength** using distance/force values captured between:

- **Index–Thumb (IT)**
- **Middle–Thumb (MT)**

Data is streamed over serial from an Arduino (or similar device) in the format:

```text
index:123,middle:145
```mermaid
flowchart TD

    A([START]) --> B[Initialize serial port]

    B --> C{Within time window?}
    C -- NO --> H[End collection]
    C -- YES --> D[Read line from serial]

    D --> E{Packet parsed OK?}
    E -- NO --> C
    E -- YES --> F[Update index and middle arrays]

    F --> C

    H --> I[Compute minima and ratios]
    I --> J[Print pinch session summary]
    J --> K([END])
```
