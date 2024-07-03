# Fur Affinity
- [Preview](#preview)
- [Project Goals](#project-goals)
- [Features](#features)
- [Installation](#installation)
  * [Installation with AltStore](#installation-with-altstore)
- [Can I trust this app?](#can-i-trust-this-app)
- [How does it get access to my account?](#how-does-it-get-access-to-my-account)
- [Will I get banned from Fur Affinity for using this app?](#will-i-get-banned-from-fur-affinity-for-using-this-app)
- [Technologies used and required iOS version](#technologies-used-and-required-ios-version)
- [Privacy policy](#privacy-policy)

## Preview

https://user-images.githubusercontent.com/451334/169599555-73412b68-0c0a-4909-b36d-2553502c3515.mp4

Thank you [Hyilpi](https://www.furaffinity.net/user/hyilpi/), [Terriniss](https://www.furaffinity.net/user/terriniss/), [tiaamaito](https://www.furaffinity.net/user/tiaamaito/) and [Hiorou](https://www.furaffinity.net/user/hiorou/) for letting me use your art in the demo ❤️.

## Project Goals
This project is written to be able to benefit from [furaffinity.net](https://www.furaffinity.net) content on iOS through a more friendly and native experience. It also serves as a learning project for the [technologies mentioned later](#technologies-and-requirements). It can also be useful to other people and is thus provided by the means of this opensource GitHub project.

## Features

- [x] Submissions feed
- [x] Notifications feed (journals, submission comments & journal comments)
- [x] Notes (read only)
- [x] In-app navigation for any submission and journal
  - [x] Submission download & fav
  - [x] Description
  - [x] Sharing and [Hand-Off](https://support.apple.com/en-gb/HT209455) support
  - [x] Comments threads (read & write)
- [x] User profile browsing:
  - [x] Main description
  - [x] Shouts
  - [x] Gallery, scraps and favorites
  - [x] Follow/unfollow
- [ ] iOS notifications
- [ ] Exploration

## Installation
The [furaffinity.net](https://www.furaffinity.net) website does not only host SFW content. This prevents such application from being distributed through Apple's App Store (although it's not stopping apps like Twitter or Bluesky, but… 🤷). Nervertheless it can still be used on your own device through sideloading (manual installation through a .ipa file), for instance with [AltStore](https://altstore.io) or, if you are a developer, [by installing the app on your device with Xcode](https://developer.apple.com/documentation/xcode/running-your-app-in-simulator-or-on-a-device). In the near future, installation should become simpler thanks to [new EU regulations forcing Apple to allow sideloading](https://developer.apple.com/support/dma-and-apps-in-the-eu/). In particular, I have plans to distribute the app through [AltStore PAL](https://rileytestut.com/blog/2024/04/17/introducing-altstore-pal/) alternative marketplace, once their developers accept submissions for third-party apps.

### Installation with AltStore
[AltStore](https://altstore.io) is an application on iPhone that can install applications to your device without needing approval from Apple. To do so, it interacts with a program named AltServer installed on your Windows or macOS computer.
- Follow [these steps](https://faq.altstore.io) to install AltStore and AltServer if not already done.
- From AltStore app on your iPhone, go to `Sources`, touch `+` icon in top left and paste the https://furaffinity-app.yalir.org/altstore.json url and touch the `+` button next to the displayed `Ceylo's Apps Hub` source to add it. This will give you access to all apps and their updates that I publish, all from within AltStore.
- Now you can find the `Fur Affinity` app from the `Browse` tab and install it. Enjoy!
<img alt="App preview in AltStore" width="585px" src="https://github.com/Ceylo/FurAffinityApp/assets/451334/6a9db988-a6d8-478a-be22-dbcb36728ff1" />

### Direct sideloading
The [releases page](https://github.com/Ceylo/FurAffinityApp/releases) provides the IPA file for each release, so you can of course sideload this file with your preferred tool.

## Can I trust this app?
The application is unofficial so you may wonder if it's trying to steal your Fur Affinity account or some other personal information. The fact that you have access to the full source code lets you check how it works and specifically the fact that no password is ever known to the application. The app also does not try to use any personal information beyond what is stricly necessary to let the application run: it reads the submissions listed on your account only to give you access to them in the app, etc.

## How does it get access to my account?
The app displays furaffinity.net login webpage to let you enter account details. These are communicated by the web browser to furaffinity.net which will then create cookies that allow your session to remain active. The account details communication only happen between the web browser and furaffinity.net server, the app only has access to the created cookies. The application then reuses these cookies to make requests to furaffinity.net as if connected with your account.

## Will I get banned from Fur Affinity for using this app?
As of May 2022, Fur Affinity staff allows the use of the application as long as it does not make excessive requests to furaffinity.net. This goes against apps that download the full gallery of a user for instance, but not against this app which, from furaffinity.net's point of view, behaves very similarly to a usual web browsing experience.

## Technologies used and required iOS version
This project is fully written in Swift and is based on SwiftUI, Swift Concurrency and other APIs introduced in iOS 16.
As such iOS 16 or later is required to run the app.

## Privacy policy
See the [Privacy Policy](Privacy%20Policy.md) page.
