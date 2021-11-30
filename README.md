# Fur Affinity
## Project Goals
This project is written to be able to benefit from [furaffinity.net](https://www.furaffinity.net) content on iOS through a more friendly and native experience. It also serves as a learning project for the [technologies mentioned below](#technologies-and-requirements). It can also be useful to other people and is thus provided by the means of this opensource GitHub project.

## Features

- [x] Submissions feed
  - [x] Submission download
  - [ ] Submission details & like
  - [ ] Submission comments
- [ ] Journals feed
- [ ] Messages reading
- [ ] Notifications
- [ ] Exploration

## Installation
The [furaffinity.net](https://www.furaffinity.net) website hosts NSFW content in addition to SFW content. Although NSFW content is not displayed unless explicitly enabled in the Fur Affinity user account settings, this prevents such application from being distributed through the official App Store. Nervertheless it can still be used on your own device through sideloading, for instance with [AltStore](https://altstore.io) or, if you are a developer, [by installing the app on your device with Xcode](https://developer.apple.com/documentation/xcode/running-your-app-in-the-simulator-or-on-a-device).

At this point no IPA is provided. This will change once the project becomes mature enough.

## Can I trust this app?
The application is unofficial so you may wonder if it's trying to steal your Fur Affinity account or some other personal information. The fact that you have access to the full source code lets you check how it works and specifically the fact that no password is ever known to the application. We also do not try to use any personal information beyond what is stricly necessary to allow the application to run: we read the submissions listed on your account to give you access to them in the app, etc.

## How does it get access to my account?
The app displays furaffinity.net login webpage to let you enter account details. These are communicated by the web browser to furaffinity.net which will then create cookies that allow your session to remain active. The account details communication only happen between the web browser and furaffinity.net server, the app only has access to the created cookies. The application then reuses these cookies to make requests to furaffinity.net as if connected with your account.

## Will I get banned from Fur Affinity for using this app?
As of July 2020, Fur Affinity staff allows the use of the application as long as it does not make excessive requests to furaffinity.net. This goes against apps that download the full gallery of a user for instance, but not against this app which, from furaffinity.net's point of view, behave very similarly to a usual browsing experience.

## Technologies and Requirements
This project is fully written in Swift and is based on SwiftUI and Swift Concurrency.
As such iOS 15 or later is required to run the app.
