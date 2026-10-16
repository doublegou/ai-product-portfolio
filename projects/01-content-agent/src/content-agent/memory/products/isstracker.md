# Product Asset: ISS Tracker iOS

## Basic Facts

- Product name: ISS Tracker
- Platform: iOS
- App category in project config: Education
- Bundle identifier: com.zhongmeng.iss-tracker
- Current version in Info.plist: 1.0
- Product type: mobile app for tracking the International Space Station
- Visual style: dark, futuristic, dashboard-like interface with cyan/green accents
- Current monetization in code: Google AdMob banner is integrated

## What It Does

ISS Tracker helps users see where the International Space Station is and when it may be visible from their location.

Core capabilities found in the code:

- Real-time ISS position tracking on a world map
- Orbit path display on a dark MapLibre map
- Daylight / night status badge for the ISS
- Live telemetry cards for latitude, longitude, speed, and altitude
- Next visible pass prediction based on the user's location
- Pass details include start time, end time, max elevation, duration, and azimuth direction
- Embedded live video feed area with HDEV and ISS Cam source switching
- Tip explaining that blue or black live-feed screens may mean signal loss zone or night side of Earth
- Local cache for ISS orbital data, with network refresh and fallback behavior

## Product Experience

First-screen experience:

- Header shows "ISS TRACKER" and current UTC time
- Main map shows ISS position, orbit path, day/night region, and user location
- A carousel switches between LIVE TELEMETRY and NEXT VISIBLE PASS
- Live feed panel sits below telemetry / pass prediction
- The whole UI feels like a compact space mission dashboard on iPhone

Tone for describing the product:

- Curious, precise, slightly cinematic
- Good framing: "a small space station control panel in your pocket"
- Good framing: "know where the ISS is before you look up"
- Good framing: "turn a casual night sky moment into something trackable"

## Target Users

- People curious about space, satellites, NASA, and the ISS
- Casual sky watchers who want to know when to look up
- Parents or teachers who want a simple educational space demo
- iPhone users who like beautiful utility apps and live dashboards
- Users who enjoy real-time data, maps, telemetry, and live feeds

## Content Angles

Useful Xiaohongshu / social content angles:

- "I put the International Space Station on my phone"
- "How to know when the ISS is passing over your city"
- "Why the ISS live feed sometimes turns blue or black"
- "A tiny space dashboard for people who like looking up at the sky"
- "The ISS is not abstract anymore when you can see its speed, altitude, and orbit"
- "A science app that makes space feel close"
- "Tonight, before you look up, check where the ISS actually is"

## What To Emphasize

- The app makes ISS movement visible and understandable
- It combines map, telemetry, pass prediction, and live feed in one screen
- It is useful for curiosity, education, and casual observation
- The design is part of the appeal: dark, technical, space-control-room feeling
- Location permission is used to calculate the next visible pass over the user's current position

## Boundaries And Claims To Avoid

Do not claim unless later confirmed:

- Do not say the app is already published on the App Store
- Do not mention price, downloads, rankings, ratings, reviews, or revenue
- Do not claim official NASA partnership or endorsement
- Do not promise the user will definitely see the ISS with the naked eye
- Do not say the app works fully offline; it uses network data and live video feeds
- Do not overpromise precision beyond what the code supports
- Do not present ads as a user benefit

Safe wording:

- "helps you track"
- "predicts upcoming visible passes based on your location"
- "shows live telemetry such as latitude, longitude, speed, and altitude"
- "includes live feed access, when the feed is available"
- "uses local cache as fallback for orbital data"
