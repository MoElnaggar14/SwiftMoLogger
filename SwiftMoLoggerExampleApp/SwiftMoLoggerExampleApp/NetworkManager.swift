import Foundation
import SwiftMoLogger

// MARK: - Network Manager

class NetworkManager: LogTagged {
    
    // MARK: - LogTagged Protocol
    var logTag: LogTag { LogTag.Network.api }
    
    // MARK: - Singleton
    static let shared = NetworkManager()
    
    private let urlSession: URLSession
    private let baseURL = "https://jsonplaceholder.typicode.com"
    
    private init() {
        // Configure URL session
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 60.0
        urlSession = URLSession(configuration: config)
        
        logInfo("Network manager initialized")
        SwiftMoLogger.info(message: "URL session configured", tag: LogTag.Network.network)
        SwiftMoLogger.info(message: "Base URL: \(baseURL)", tag: LogTag.Network.network)
    }
    
    // MARK: - Public API
    
    func fetchUserData() {
        logInfo("Starting user data fetch")
        SwiftMoLogger.info(message: "API call initiated: GET /users/1", tag: LogTag.Network.api)
        
        guard let url = URL(string: "\(baseURL)/users/1") else {
            logError("Invalid URL for user data endpoint")
            return
        }
        
        // Log request details
        SwiftMoLogger.info(message: "Making HTTP request", tag: LogTag.Network.network)
        SwiftMoLogger.debug(message: "Request URL: \(url.absoluteString)", tag: LogTag.debug)
        
        let task = urlSession.dataTask(with: url) { [weak self] data, response, error in
            self?.handleUserDataResponse(data: data, response: response, error: error)
        }
        
        task.resume()
        SwiftMoLogger.info(message: "Network request dispatched", tag: LogTag.Network.network)
    }
    
    func fetchPosts() {
        logInfo("Fetching posts data")
        SwiftMoLogger.info(message: "API call initiated: GET /posts", tag: LogTag.Network.api)
        
        guard let url = URL(string: "\(baseURL)/posts") else {
            logError("Invalid URL for posts endpoint")
            return
        }
        
        performRequest(url: url, operation: "fetchPosts") { [weak self] data, response, error in
            self?.handlePostsResponse(data: data, response: response, error: error)
        }
    }
    
    func uploadData(_ data: Data) {
        logInfo("Starting data upload")
        SwiftMoLogger.info(message: "Upload initiated", tag: LogTag.Network.upload)
        SwiftMoLogger.info(message: "Data size: \(data.count) bytes", tag: LogTag.Network.upload)
        
        guard let url = URL(string: "\(baseURL)/posts") else {
            logError("Invalid URL for upload endpoint")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        
        SwiftMoLogger.info(message: "Upload request configured", tag: LogTag.Network.upload)
        
        let task = urlSession.dataTask(with: request) { [weak self] data, response, error in
            self?.handleUploadResponse(data: data, response: response, error: error)
        }
        
        task.resume()
        SwiftMoLogger.info(message: "Upload request dispatched", tag: LogTag.Network.upload)
    }
    
    // MARK: - Private Methods
    
    private func performRequest(
        url: URL,
        operation: String,
        completion: @escaping (Data?, URLResponse?, Error?) -> Void
    ) {
        SwiftMoLogger.info(message: "Performing \(operation) request", tag: LogTag.Network.network)
        SwiftMoLogger.crash(message: "Critical network operation: \(operation)")
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let task = urlSession.dataTask(with: url) { data, response, error in
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            SwiftMoLogger.info(message: "\(operation) completed in \(String(format: "%.3f", duration))s", tag: LogTag.System.performance)
            
            completion(data, response, error)
        }
        
        task.resume()
    }
    
    // MARK: - Response Handlers
    
    private func handleUserDataResponse(data: Data?, response: URLResponse?, error: Error?) {
        logInfo("Processing user data response")
        
        if let error = error {
            logError("User data fetch failed")
            SwiftMoLogger.error(message: "Network error: \(error.localizedDescription)", tag: LogTag.Network.network)
            handleNetworkError(error)
            return
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            logError("Invalid response type")
            SwiftMoLogger.error(message: "Invalid HTTP response", tag: LogTag.Network.api)
            return
        }
        
        SwiftMoLogger.info(message: "HTTP status: \(httpResponse.statusCode)", tag: LogTag.Network.api)
        
        if httpResponse.statusCode == 200 {
            logInfo("User data fetch successful")
            SwiftMoLogger.info(message: "User data received successfully", tag: LogTag.Network.api)
            
            if let data = data {
                parseUserData(data)
            }
        } else {
            logError("HTTP error: \(httpResponse.statusCode)")
            SwiftMoLogger.error(message: "API error: HTTP \(httpResponse.statusCode)", tag: LogTag.Network.api)
        }
    }
    
    private func handlePostsResponse(data: Data?, response: URLResponse?, error: Error?) {
        logInfo("Processing posts response")
        
        if let error = error {
            logError("Posts fetch failed")
            SwiftMoLogger.error(message: "Posts API error: \(error.localizedDescription)", tag: LogTag.Network.api)
            return
        }
        
        guard let data = data else {
            logError("No data received for posts")
            SwiftMoLogger.error(message: "Empty response data", tag: LogTag.Network.api)
            return
        }
        
        logInfo("Posts data received")
        SwiftMoLogger.info(message: "Posts data size: \(data.count) bytes", tag: LogTag.Network.api)
        
        // Simulate caching
        SwiftMoLogger.info(message: "Caching posts data", tag: LogTag.Data.cache)
    }
    
    private func handleUploadResponse(data: Data?, response: URLResponse?, error: Error?) {
        logInfo("Processing upload response")
        
        if let error = error {
            logError("Upload failed")
            SwiftMoLogger.error(message: "Upload error: \(error.localizedDescription)", tag: LogTag.Network.upload)
            
            // Log retry logic
            SwiftMoLogger.info(message: "Queuing upload for retry", tag: LogTag.Network.upload)
            return
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            logError("Invalid upload response")
            return
        }
        
        if httpResponse.statusCode == 201 {
            logInfo("Upload completed successfully")
            SwiftMoLogger.info(message: "Data uploaded successfully", tag: LogTag.Network.upload)
            
            // Log analytics event
            SwiftMoLogger.info(message: "Upload success event", tag: LogTag.ThirdParty.analytics)
        } else {
            logError("Upload failed with HTTP \(httpResponse.statusCode)")
            SwiftMoLogger.error(message: "Upload failed: HTTP \(httpResponse.statusCode)", tag: LogTag.Network.upload)
        }
    }
    
    // MARK: - Data Processing
    
    private func parseUserData(_ data: Data) {
        SwiftMoLogger.info(message: "Parsing user data", tag: LogTag.Business.workflow)
        SwiftMoLogger.info(message: "Raw data size: \(data.count) bytes", tag: LogTag.Data.parsing)
        
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            SwiftMoLogger.info(message: "JSON parsing successful", tag: LogTag.Data.parsing)
            SwiftMoLogger.debug(message: "Parsed JSON object", tag: LogTag.debug)
            
            // Simulate data validation
            validateUserData(json)
            
        } catch {
            logError("Failed to parse user data JSON")
            SwiftMoLogger.error(message: "JSON parsing failed: \(error.localizedDescription)", tag: LogTag.Data.parsing)
        }
    }
    
    private func validateUserData(_ json: Any) {
        SwiftMoLogger.info(message: "Validating user data", tag: LogTag.Business.validation)
        
        guard let userDict = json as? [String: Any] else {
            SwiftMoLogger.error(message: "Invalid user data format", tag: LogTag.Business.validation)
            return
        }
        
        // Check required fields
        let requiredFields = ["id", "name", "email"]
        for field in requiredFields {
            if userDict[field] == nil {
                SwiftMoLogger.error(message: "Missing required field: \(field)", tag: LogTag.Business.validation)
                return
            }
        }
        
        SwiftMoLogger.info(message: "User data validation passed", tag: LogTag.Business.validation)
        
        // Store user data
        SwiftMoLogger.info(message: "Storing user data", tag: LogTag.Data.userdefaults)
    }
    
    // MARK: - Error Handling
    
    private func handleNetworkError(_ error: Error) {
        SwiftMoLogger.info(message: "Handling network error", tag: LogTag.Network.network)
        
        if (error as NSError).code == NSURLErrorTimedOut {
            logWarn("Request timed out")
            SwiftMoLogger.warn(message: "Network timeout detected", tag: LogTag.Network.network)
            SwiftMoLogger.info(message: "Implementing retry logic", tag: LogTag.Network.network)
        } else if (error as NSError).code == NSURLErrorNotConnectedToInternet {
            logError("No internet connection")
            SwiftMoLogger.error(message: "Internet connection unavailable", tag: LogTag.Network.network)
            SwiftMoLogger.info(message: "Switching to offline mode", tag: LogTag.Data.cache)
        } else {
            logError("Network error occurred")
            SwiftMoLogger.error(message: "Unhandled network error", tag: LogTag.Network.network)
        }
        
        // Log error analytics
        SwiftMoLogger.info(message: "Network error event tracked", tag: LogTag.ThirdParty.analytics)
    }
    
    // MARK: - Connection Monitoring
    
    func checkNetworkStatus() {
        logInfo("Checking network connectivity")
        SwiftMoLogger.info(message: "Network status check initiated", tag: LogTag.Network.network)
        
        // Simulate network check
        let isConnected = true // In real app, use proper network monitoring
        
        if isConnected {
            SwiftMoLogger.info(message: "Network connection available", tag: LogTag.Network.network)
        } else {
            SwiftMoLogger.warn(message: "Network connection unavailable", tag: LogTag.Network.network)
            SwiftMoLogger.info(message: "Activating offline mode", tag: LogTag.System.lifecycle)
        }
    }
    
    deinit {
        logInfo("Network manager deallocated")
        SwiftMoLogger.info(message: "Network resources released", tag: LogTag.System.memory)
    }
}