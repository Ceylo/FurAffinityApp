//
//  NotificationViewController.swift
//  NotificationContent
//
//  Created by Ceylo on 04/06/2026.
//

import UIKit
import UserNotifications
import UserNotificationsUI

/// Custom expanded view for submission notifications. The banner / lock screen show
/// the notification's primary attachment (the clear thumbnail for general submissions,
/// or the blurred thumbnail for mature/adult). On long-press / expand this controller
/// renders the `"clear"` attachment, revealing the unblurred thumbnail.
class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private let imageView = UIImageView()

    override func viewDidLoad() {
        super.viewDidLoad()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func didReceive(_ notification: UNNotification) {
        let attachments = notification.request.content.attachments
        // Prefer the clear image; fall back to the first attachment.
        guard let attachment = attachments.first(where: { $0.identifier == "clear" }) ?? attachments.first else {
            return
        }

        guard attachment.url.startAccessingSecurityScopedResource() else {
            return
        }
        defer { attachment.url.stopAccessingSecurityScopedResource() }

        guard let image = UIImage(contentsOfFile: attachment.url.path) else {
            return
        }
        imageView.image = image

        // Size the expanded view to the image's aspect ratio.
        let width = max(view.bounds.width, 1)
        let aspect = image.size.height / max(image.size.width, 1)
        preferredContentSize = CGSize(width: width, height: width * aspect)
    }
}
