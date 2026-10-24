# VisionPath AI - Project Identity and Overview

## 1. Project Identity

**Project Name:** VisionPath AI  
**Application ID:** com.example.visionpath  
**Version:** 1.0.0+1  
**Package:** com.example.visionpath  
**Development Tool:** Flutter (Dart SDK ^3.13.3)  
**Platform:** Android (Mobile - Android only in current implementation)

## 2. Project Purpose and Domain

VisionPath AI is an AI-powered accessibility application designed to assist individuals with visual impairments or limited vision. It provides real-time environmental awareness, object detection, face recognition, text reading, and emergency assistance through a smartphone camera interface.

### 2.1 Problem Domain

The application addresses the challenges faced by people with visual impairments in daily navigation and object identification. It bridges the gap between what users can see and what they need to know about their environment through:

- Real-time obstacle detection and path analysis
- Familiar face recognition for social interaction support
- Text reading from images and documents
- Currency recognition for financial independence
- Emergency SOS functionality for safety

### 2.2 Target Users

- Individuals with visual impairments (blind or low vision)
- People with limited mobility who benefit from voice-guided interfaces
- Elderly users who may experience age-related vision decline
- Caregivers who need emergency notification features

### 2.3 Core Objectives

1. **Environmental Awareness:** Provide real-time audio descriptions of surroundings
2. **Independent Navigation:** Help users navigate safely using object detection and path analysis
3. **Social Interaction:** Recognize and announce familiar faces during encounters
4. **Accessibility:** Offer voice-guided text reading and currency identification
5. **Emergency Safety:** Enable quick emergency contact initiation via press-and-hold gesture

### 2.4 Expected Benefits

- Increased independence in daily activities
- Improved safety during navigation
- Enhanced social confidence through face recognition
- Financial empowerment through currency recognition
- Peace of mind with emergency assistance

### 2.5 Assumptions and Constraints

**Assumptions:**
- Users have access to an Android device with a camera
- Device has sufficient processing power for on-device ML inference
- Users are comfortable with voice-first interfaces
- No internet connection is required for core AI features

**Constraints:**
- Android-only support (no iOS or web deployment)
- On-device inference limits model complexity
- Battery life constraints for continuous camera use
- No backend/cloud infrastructure (all processing local)

## 3. Existing System Limitations (Addressed by VisionPath)

- Commercial solutions often require internet connectivity
- Many apps focus on single functionality rather than integrated suite
- Voice guidance quality and naturalness varies significantly
- Complex setup processes deter adoption by elderly users
- Lack of integrated emergency features

## 4. Proposed System Advantages

- **Offline-capable AI:** All models run locally for privacy and reliability
- **Integrated suite:** Multiple assistive features in one application
- **Privacy-first:** No data leaves the device
- **Voice-first design:** Optimized for users who cannot see the screen
- **Emergency integration:** Built-in SOS with location sharing

## 5. Scope

### 5.1 In-Scope Features

- Real-time object detection and classification (people, vehicles, furniture, etc.)
- Path analysis and navigation guidance (forward, left, right, stop)
- Familiar face registration and recognition with voice announcements
- Real-time text reading with OCR
- Currency note and coin identification
- Emergency SOS with call and SMS functionality
- Voice-guided assistance with press-and-hold commands
- Comprehensive settings for customization
- Depth estimation for object proximity

### 5.2 Out-of-Scope

- Cloud-based AI processing
- Cross-platform deployment (iOS, web)
- Social sharing or social media integration
- Wearable device support (smart glasses, watches)
- Prosthetic device integration

## 6. Domain Terminology

- **Face Embedding:** Numerical representation of facial features for comparison
- **YOLO (You Only Look Once):** Real-time object detection algorithm
- **SCRFD:** Sample and Computation Redistribution for Face Detection
- **ArcFace:** Deep learning-based face recognition model
- **MobileFaceNet:** Lightweight face embedding model
- **ML Kit:** Google's on-device machine learning SDK
- **OCR (Optical Character Recognition):** Text extraction from images
- **TTS (Text-to-Speech):** Speech synthesis from text
- **SOS (Save Our Souls):** Emergency distress signal system
