/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller that recognizes and tracks images found in the user's environment.
*/

import ARKit
import Foundation
import SceneKit
import UIKit
import Vision


class ViewController: UIViewController {

    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var messagePanel: UIView!
    @IBOutlet weak var messageLabel: UILabel!

    static var instance: ViewController?
    
    /// An object that detects rectangular shapes in the user's environment.
    let rectangleDetector = RectangleDetector()
    
    /// An object that represents an augmented image that exists in the user's environment.
    var alteredImage: AlteredImage?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        rectangleDetector.delegate = self
        sceneView.delegate = self
    }

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
        ViewController.instance = self
		
		// Prevent the screen from being dimmed after a while.
		UIApplication.shared.isIdleTimerDisabled = true
        
        searchForNewImageToTrack()
	}
    
    func searchForNewImageToTrack() {
        alteredImage?.delegate = nil
        alteredImage = nil
        
        // Restart the session and remove any image anchors that may have been detected previously.
        runImageTrackingSession(with: [], runOptions: [.removeExistingAnchors, .resetTracking])
        
        showMessage("Look for a rectangular image.", autoHide: false)
    }
    
    /// - Tag: ImageTrackingSession
    private func runImageTrackingSession(with trackingImages: Set<ARReferenceImage>,
                                         runOptions: ARSession.RunOptions = [.removeExistingAnchors]) {
        let configuration = ARImageTrackingConfiguration()
        configuration.maximumNumberOfTrackedImages = 1
        configuration.trackingImages = trackingImages
        sceneView.session.run(configuration, options: runOptions)
    }
    
    // The timer for message presentation.
    private var messageHideTimer: Timer?
    
    func showMessage(_ message: String, autoHide: Bool = true) {
        DispatchQueue.main.async {
            self.messageLabel.text = message
            self.setMessageHidden(false)
            
            self.messageHideTimer?.invalidate()
            if autoHide {
                self.messageHideTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                    self?.setMessageHidden(true)
                }
            }
        }
    }
    
    private func setMessageHidden(_ hide: Bool) {
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState], animations: {
                self.messagePanel.alpha = hide ? 0 : 1
            })
        }
    }
    
    /// Handles tap gesture input.
    @IBAction func didTap(_ sender: Any) {
        alteredImage?.pauseOrResumeFade()
    }
}

extension ViewController: ARSCNViewDelegate {
    
    /// - Tag: ImageWasRecognized
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        alteredImage?.add(anchor, node: node)
        setMessageHidden(true)
    }

    /// - Tag: DidUpdateAnchor
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        alteredImage?.update(anchor)
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        guard let arError = error as? ARError else { return }
        
        if arError.code == .invalidReferenceImage {
            // Restart the experience, as otherwise the AR session remains stopped.
            // There's no benefit in surfacing this error to the user.
            print("Error: The detected rectangle cannot be tracked.")
            searchForNewImageToTrack()
            return
        }
        
        let errorWithInfo = arError as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        
        // Use `compactMap(_:)` to remove optional error messages.
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        
        DispatchQueue.main.async {
            
            // Present an alert informing about the error that just occurred.
            let alertController = UIAlertController(title: "The AR session failed.", message: errorMessage, preferredStyle: .alert)
            let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
                alertController.dismiss(animated: true, completion: nil)
                self.searchForNewImageToTrack()
            }
            alertController.addAction(restartAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }
}

extension ViewController: RectangleDetectorDelegate {
    /// Called when the app recognized a rectangular shape in the user's envirnment.
    /// - Tag: CreateReferenceImage
    func rectangleFound(rectangleContent: CIImage) {
        DispatchQueue.main.async {
            do {
                let model = try VNCoreMLModel(for: Simple().model)
                
                let request = VNCoreMLRequest(model: model, completionHandler: { request, error in
                    for observation in request.results! where observation is VNRecognizedObjectObservation {
                        guard let objectObservation = observation as? VNRecognizedObjectObservation else {
                            continue
                        }
                        
                        // Select only the label with the highest confidence.
                        let confidentLabels = objectObservation.labels.filter({ (label) -> Bool in
                            return label.confidence > 0.7
                        })
                        
                        let c = confidentLabels.first
                        if(c != nil) {
                            self.showMessage(" \(request.results!.count) \(c!.identifier) confidence: \(c!.confidence)")
                        }
                    }
                })
                

                let handler = VNImageRequestHandler(ciImage: rectangleContent, orientation: .up)
                do {
                    try handler.perform([request])
                } catch {

                    print("Failed to perform new classification.\n\(error)")
                }
            } catch {
                fatalError("Failed to load Vision ML model: \(error)")
            }
        }
    }
}

/// Enables the app to create a new image from any rectangular shapes that may exist in the user's environment.
extension ViewController: AlteredImageDelegate {
    func alteredImageLostTracking(_ alteredImage: AlteredImage) {
        searchForNewImageToTrack()
    }
}
