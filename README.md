# Fur Affinity
- [Preview](#preview)
- [Project Goals](#project-goals)
- [Features](#features)
- [Installation](#installation)
- [Can I trust this app?](#can-i-trust-this-app)
- [How does it get access to my account?](#how-does-it-get-access-to-my-account)
- [Will I get banned from Fur Affinity for using this app?](#will-i-get-banned-from-fur-affinity-for-using-this-app)
- [Technologies used and required iOS version](#technologies-used-and-required-ios-version)
- [Privacy policy](#privacy-policy)

## Preview

See the screenshots on [furaffinity.app](https://furaffinity.app)!

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
See the steps on the official website: [furaffinity.app](https://furaffinity.app).

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
