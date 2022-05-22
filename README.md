# Fur Affinity
## Preview

https://user-images.githubusercontent.com/451334/169599555-73412b68-0c0a-4909-b36d-2553502c3515.mp4

Artists featured in this video with their consent: [Hyilpi](https://www.furaffinity.net/user/hyilpi/), [Terriniss](https://www.furaffinity.net/user/terriniss/), [tiaamaito](https://www.furaffinity.net/user/tiaamaito/) and [Hiorou](https://www.furaffinity.net/user/hiorou/).

## Project Goals
This project is written to be able to benefit from [furaffinity.net](https://www.furaffinity.net) content on iOS through a more friendly and native experience. It also serves as a learning project for the [technologies mentioned below](#technologies-and-requirements). It can also be useful to other people and is thus provided by the means of this opensource GitHub project.

## Features

- [x] Submissions feed
  - [x] Submission download
  - [x] Submission details
  - [ ] Submission like
  - [ ] Submission comments
- [ ] Journals feed
- [x] Messages reading
- [ ] Notifications
- [ ] Exploration

## Installation
The [furaffinity.net](https://www.furaffinity.net) website hosts NSFW content in addition to SFW content. This prevents such application from being distributed through the official App Store. Nervertheless it can still be used on your own device through sideloading (manual installation through a .ipa file), for instance with [AltStore](https://altstore.io) or, if you are a developer, [by installing the app on your device with Xcode](https://developer.apple.com/documentation/xcode/running-your-app-in-the-simulator-or-on-a-device). In the future installation may become simpler thanks to [new EU regulations forcing Apple to allow sideloading](https://www.theverge.com/2022/3/25/22996248/apple-sideloading-apps-store-third-party-eu-dma-requirement).

### Installation with AltStore
[AltStore](https://altstore.io) is an application on iPhone that can install applications to your device without needing approval from Apple. To do so, it interacts with a program named AltServer installed on your Windows or macOS computer.
- Follow [these steps](https://faq.altstore.io) to install AltStore and AltServer if not already done. 
- From your iPhone web browser, go the [releases](https://github.com/Ceylo/FurAffinityApp/releases) page and download the latest IPA file.
- From AltStore app on your iPhone, go to "My Apps" tab, touch "+" icon in top left and select the IPA file you just downloaded.

## Can I trust this app?
The application is unofficial so you may wonder if it's trying to steal your Fur Affinity account or some other personal information. The fact that you have access to the full source code lets you check how it works and specifically the fact that no password is ever known to the application. The app also does not try to use any personal information beyond what is stricly necessary to let the application run: it reads the submissions listed on your account only to give you access to them in the app, etc.

## How does it get access to my account?
The app displays furaffinity.net login webpage to let you enter account details. These are communicated by the web browser to furaffinity.net which will then create cookies that allow your session to remain active. The account details communication only happen between the web browser and furaffinity.net server, the app only has access to the created cookies. The application then reuses these cookies to make requests to furaffinity.net as if connected with your account.

## Will I get banned from Fur Affinity for using this app?
As of July 2020, Fur Affinity staff allows the use of the application as long as it does not make excessive requests to furaffinity.net. This goes against apps that download the full gallery of a user for instance, but not against this app which, from furaffinity.net's point of view, behave very similarly to a usual browsing experience.
I have asked FA staff for an update on this in December 2021 but did not get any answer for now. By default I consider it is still fine.

## Technologies and Requirements
This project is fully written in Swift and is based on SwiftUI and Swift Concurrency.
As such iOS 15 or later is required to run the app.
