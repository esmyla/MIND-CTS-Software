# Software Team Goals

As the software team for this project, our mission is to design and build an AWS-hosted application that acts as the primary interface for visualizing, tracking, and analyzing patient rehabilitation data. Our work will focus on creating a platform that combines real-time activity tracking with long-term progress analysis, ensuring that users (patients and clinicians) have meaningful insights into recovery and therapy outcomes.  

## Core Objectives  

### 1. Physical Therapy Exercise Tracking (Camera-Based)  
- Build an interactive page where users can select from a library of physical therapy exercises.  
- Use the user’s camera to track hand movements as they perform the exercise.  
- Store and display the accuracy of each exercise attempt.  
- Implement graphing functionality to visualize exercise accuracy over time, modeled after the performance graphs used in stock market applications.  

### 2. Grip Strength Monitoring (FSR Sensor Data)  
- Create a page dedicated to visualizing grip strength data collected from the glove’s Force Sensitive Resistor (FSR) sensors.  
- Log grip strength values for each session.  
- Provide performance graphs that show grip strength progression across multiple sessions, again using a stock-style UI for clarity and familiarity.  

### 3. Strain and Exertion Analysis (Heart Rate Integration)  
- Simultaneously capture data from the glove’s heart rate sensor while grip strength is measured.  
- Use this data to evaluate the physiological strain associated with each exercise.  
- Develop a combined **strength + exertion metric**, tracked and displayed over time, to give a more holistic view of the user’s physical performance and recovery progress.  

---

## Overall Goal  

Our end product should not only provide raw metrics, but also deliver them in a way that feels intuitive, motivating, and clinically useful. By integrating camera-based tracking with sensor data, and combining them into clear, visual progress reports, we will create a robust tool for rehabilitation support.  

---
## 🛠️ Phase-by-Phase Roadmap  

### Phase 1: Core Infrastructure & Setup  
**Goal:** Lay the foundation for the entire application.  
- Set up AWS hosting environment.  
- Create the base React + TypeScript application framework.  
- Establish a database schema (Supabase/Postgres) for storing user session data.  
- Build basic user login and authentication.  

---

### Phase 2: Camera-Based Exercise Tracking Prototype  
**Goal:** Enable real-time tracking of therapy exercises.  
- Implement camera input with hand tracking (MediaPipe / TensorFlow.js).  
- Build UI for exercise selection.  
- Capture accuracy metrics for each exercise attempt.  
- Store attempt data in the database.  
- Display accuracy results in a simple time-series graph.  

---

### Phase 3: Grip Strength Data Integration  
**Goal:** Connect hardware glove data to the application.  
- Connect FSR glove sensors to stream grip strength data.  
- Build a pipeline for logging grip strength sessions.  
- Create visual graphs for grip strength progression across multiple sessions.  

---

### Phase 4: Heart Rate & Exertion Metrics  
**Goal:** Measure physical strain alongside strength data.  
- Capture heart rate sensor data in parallel with grip strength.  
- Calculate a combined **strength + exertion** metric.  
- Visualize the metric over time in graph form.  

---

### Phase 5: Unified Dashboard & Polish  
**Goal:** Deliver a clean, user-friendly experience.  
- Create a central dashboard to view exercises, grip strength, and exertion data.  
- Add visual refinements to graphs (stock-style UI).  
- Ensure data persistence, accessibility, and clarity.  
- Conduct thorough usability, accuracy, and performance testing.  
