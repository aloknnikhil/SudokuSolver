/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Contains the tracker processing logic using Vision.
*/

import AVFoundation
import UIKit
import Vision

enum VisionTrackerProcessorError: Error {
    case readerInitializationFailed
    case firstFrameReadFailed
    case objectTrackingFailed
    case rectangleDetectionFailed
}

protocol VisionTrackerProcessorDelegate: class {
    func displayFrame(_ frame: CVPixelBuffer?, withAffineTransform transform: CGAffineTransform, rects: [TrackedPolyRect]?)
    func displayFrameCounter(_ frame: Int)
    func didFinifshTracking()
}

class VisionTrackerProcessor {
    var videoAsset: AVAsset!
    var trackingLevel = VNRequestTrackingLevel.accurate
    var objectsToTrack = [TrackedPolyRect]()
    weak var delegate: VisionTrackerProcessorDelegate?

    private var cancelRequested = false
    private var initialRectObservations = [VNRectangleObservation]()

    init(videoAsset: AVAsset) {
        self.videoAsset = videoAsset
    }
    
    /// - Tag: SetInitialCondition
    func readAndDisplayFirstFrame(performRectanglesDetection: Bool) throws {
        guard let videoReader = VideoReader(videoAsset: videoAsset) else {
            throw VisionTrackerProcessorError.readerInitializationFailed
        }
        guard let firstFrame = videoReader.nextFrame() else {
            throw VisionTrackerProcessorError.firstFrameReadFailed
        }
        
        var firstFrameRects: [TrackedPolyRect]? = nil
        if performRectanglesDetection {
            // Vision Rectangle Detection
            let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: firstFrame, orientation: videoReader.orientation, options: [:])
            
            let rectangleDetectionRequest = VNDetectRectanglesRequest()
            rectangleDetectionRequest.minimumAspectRatio = VNAspectRatio(0.2)
            rectangleDetectionRequest.maximumAspectRatio = VNAspectRatio(1.0)
            rectangleDetectionRequest.minimumSize = Float(0.05)
            rectangleDetectionRequest.maximumObservations = Int(100)
            
            do {
                try imageRequestHandler.perform([rectangleDetectionRequest])
            } catch {
                throw VisionTrackerProcessorError.rectangleDetectionFailed
            }

            if let rectObservations = rectangleDetectionRequest.results as? [VNRectangleObservation] {
                initialRectObservations = rectObservations
                var detectedRects = [TrackedPolyRect]()
                for (index, rectangleObservation) in initialRectObservations.enumerated() {
                    let rectColor = TrackedObjectsPalette.color(atIndex: index)
                    let polyRect = TrackedPolyRect(observation: rectangleObservation, color: rectColor)
                    let leftDistance = CGPointDistance(from: polyRect.bottomLeft, to: polyRect.topLeft)
                    let rightDistance = CGPointDistance(from: polyRect.bottomRight, to: polyRect.topRight)
                    let topDistance = CGPointDistance(from: polyRect.topLeft, to: polyRect.topRight)
                    let bottomDistance = CGPointDistance(from: polyRect.bottomLeft, to: polyRect.bottomRight)
                    //print("Left: ", leftDistance)
                    //print("Right: ", rightDistance)
                    let verticalDiff = abs(leftDistance - rightDistance)
                    let horizontalDiff = abs(topDistance - bottomDistance)
                        let threshold = CGFloat(0.1)
                    //let threshold = CGFloat(0.9) *  min(leftDistance, rightDistance, topDistance, bottomDistance)
                    if (abs(topDistance - leftDistance) <= threshold &&
                        abs(leftDistance - bottomDistance) <= threshold &&
                        abs(bottomDistance - rightDistance) <= threshold &&
                        abs(rightDistance - topDistance) <= threshold) {
                        detectedRects.append(polyRect)
                    } else {
                        print("Diff: ", abs(topDistance - threshold))
                        //detectedRects.append(polyRect)
                    }
                }
                //print(detectedRects)
                firstFrameRects = detectedRects
            }
        }
        
        delegate?.displayFrame(firstFrame, withAffineTransform: videoReader.affineTransform, rects: firstFrameRects)
    }

    /// - Tag: PerformRequests
    func performTracking(type: TrackedObjectType) throws {
        guard let videoReader = VideoReader(videoAsset: videoAsset) else {
            throw VisionTrackerProcessorError.readerInitializationFailed
        }

        guard videoReader.nextFrame() != nil else {
            throw VisionTrackerProcessorError.firstFrameReadFailed
        }
        
        cancelRequested = false
        
        // Create initial observations
        var inputObservations = [UUID: VNDetectedObjectObservation]()
        var trackedObjects = [UUID: TrackedPolyRect]()
        switch type {
        case .object:
            for rect in self.objectsToTrack {
                let inputObservation = VNDetectedObjectObservation(boundingBox: rect.boundingBox)
                inputObservations[inputObservation.uuid] = inputObservation
                trackedObjects[inputObservation.uuid] = rect
            }
        case .rectangle:
            for rectangleObservation in initialRectObservations {
                inputObservations[rectangleObservation.uuid] = rectangleObservation
                let rectColor = TrackedObjectsPalette.color(atIndex: trackedObjects.count)
                trackedObjects[rectangleObservation.uuid] = TrackedPolyRect(observation: rectangleObservation, color: rectColor)
            }
        }
        let requestHandler = VNSequenceRequestHandler()
        var frames = 1
        var trackingFailedForAtLeastOneObject = false

        while true {
            guard cancelRequested == false, let frame = videoReader.nextFrame() else {
                break
            }

            delegate?.displayFrameCounter(frames)
            frames += 1
            
            var rects = [TrackedPolyRect]()
            var trackingRequests = [VNRequest]()
            for inputObservation in inputObservations {
                let request: VNTrackingRequest!
                switch type {
                case .object:
                    request = VNTrackObjectRequest(detectedObjectObservation: inputObservation.value)
                case .rectangle:
                    guard let rectObservation = inputObservation.value as? VNRectangleObservation else {
                        continue
                    }
                    request = VNTrackRectangleRequest(rectangleObservation: rectObservation)
                }
                request.trackingLevel = trackingLevel
             
                trackingRequests.append(request)
            }
            
            // Perform array of requests
            do {
                try requestHandler.perform(trackingRequests, on: frame, orientation: videoReader.orientation)
            } catch {
                trackingFailedForAtLeastOneObject = true
            }

            for processedRequest in trackingRequests {
                guard let results = processedRequest.results as? [VNObservation] else {
                    continue
                }
                guard let observation = results.first as? VNDetectedObjectObservation else {
                    continue
                }
                // Assume threshold = 0.5f
                let rectStyle: TrackedPolyRectStyle = observation.confidence > 0.5 ? .solid : .dashed
                let knownRect = trackedObjects[observation.uuid]!
                switch type {
                case .object:
                    rects.append(TrackedPolyRect(observation: observation, color: knownRect.color, style: rectStyle))
                case .rectangle:
                    guard let rectObservation = observation as? VNRectangleObservation else {
                        break
                    }
                    rects.append(TrackedPolyRect(observation: rectObservation, color: knownRect.color, style: rectStyle))
                }
                // Initialize inputObservation for the next iteration
                inputObservations[observation.uuid] = observation
            }

            // Draw results
            delegate?.displayFrame(frame, withAffineTransform: videoReader.affineTransform, rects: rects)

            usleep(useconds_t(videoReader.frameRateInSeconds))
        }

        delegate?.didFinifshTracking()
        
        if trackingFailedForAtLeastOneObject {
            throw VisionTrackerProcessorError.objectTrackingFailed
        }
    }
        
    func cancelTracking() {
        cancelRequested = true
    }
}
