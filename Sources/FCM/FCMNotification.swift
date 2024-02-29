public struct FCMNotification: Codable {
    /// The notification's title.
    var title: String
    
    /// The notification's body text.
    var body: String
    var image: String = ""
    /// - parameters:
    ///     - title: The notification's title.
    ///     - body: The notification's body text.
    public init(title: String, body: String, image: String = "") {
        self.title = title
        self.body = body
        self.image = image
    }
}
