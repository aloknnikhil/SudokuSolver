# Tracking Multiple Objects or Rectangles in Video

Apply Vision algorithms to track rectangles and objects throughout a video.

## Overview

With the [Vision](https://developer.apple.com/documentation/vision) framework, you can detect and track objects and rectangles through a sequence of frames coming from video, live capture, or other sources.

This sample app supports rectangle tracking as well as object tracking.  It shows you how to pick an initial object to track, how to create Vision tracking requests to follow that object, and how to parse results from the object tracker.

## Preview the Sample App

To see this sample app in action, build and run the project in Xcode, then choose a video from your photo library.  Once the video is loaded from your photo library, choose to track either objects or rectangles.

## Nominate Objects or Rectangles to Track

To track rectangles, select Rectangles.  The app will run the rectangle detector and show rectangles it found on the screen.

To track objects, select Objects and nominate objects to track by touching and dragging boxes around them in the preview.  You can select multiple objects; the app will identify them by their [`UUID`](https://developer.apple.com/documentation/foundation/uuid) with differently colored rectangles.

The [`VNTrackObjectRequest`](https://developer.apple.com/documentation/vision/vntrackobjectrequest) class requires a detected object observation to initialize.  The sample provides this observation by running [`VNDetectRectanglesRequest`](https://developer.apple.com/documentation/vision/vndetectrectanglesrequest), or by creating one from the bounding box you drew on the preview frame.  It tracks multiple objects by iterating through each observation and creating a [`VNDetectedObjectObservation`](https://developer.apple.com/documentation/vision/vndetectedobjectobservation) from its bounding box.

``` swift
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
```
[View in Source](x-source-tag://SetInitialCondition)

In your own app, if you prefer to nominate objects programmatically, you can use observations returned from Vision’s own object detection algorithms.  For example, the Vision framework’s [`VNImageRequestHandler`](https://developer.apple.com/documentation/vision/vnimagerequesthandler) accepts face detection, text detection, and barcode detection requests, and those requests return their results in subclasses of [`VNObservation`](https://developer.apple.com/documentation/vision/vnobservation).  You can pass these observations directly into [`VNTrackObjectRequest`](https://developer.apple.com/documentation/vision/vntrackobjectrequest).

Selecting a salient object heavily influences the performance of the tracking algorithm; provide the best initial bounding box segmentation of your object that you can.

## Track Objects or Rectangles with a Request Handler

The Vision framework handles tracking requests through a [`VNSequenceRequestHandler`](https://developer.apple.com/documentation/vision/vnsequencerequesthandler).  Whereas the [`VNImageRequestHandler`](https://developer.apple.com/documentation/vision/vnimagerequesthandler) handles object detection requests on a still image, the [`VNSequenceRequestHandler`](https://developer.apple.com/documentation/vision/vnsequencerequesthandler) handles tracking requests.  

Create a tracking request for each rectangle or object you’d like to track.  Seed each tracking request with the observation created during nomination.

``` swift
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
```

For each such request, call the sequence request handler’s [`perform(_:)`](https://developer.apple.com/documentation/vision/vnsequencerequesthandler/2880308-perform) method, making sure to pass in the video reader's orientation to ensure upright tracking. This method runs synchronously; use a background queue, such as `workQueue` in the sample code, so that the main queue isn't blocked while your requests execute.

``` swift
try requestHandler.perform(trackingRequests, on: frame, orientation: videoReader.orientation)
```
[View in Source](x-source-tag://PerformRequests)

By iterating through each selected object or rectangle, creating a tracking request from it, and calling perform on the request handler, Vision follows the object or rectangle over the image sequence and return results through its `results` property.


## Interpret Tracking Results

Access tracking results through the request's `results` property, or its completion handler.  A single tracking request represents a single tracked object in a one-to-one relationship.  If a tracking request succeeds, its [`results`](https://developer.apple.com/documentation/vision/vnrequest/2867238-results) property contains [`VNDetectedObjectObservation`](https://developer.apple.com/documentation/vision/vndetectedobjectobservation) objects describing the tracked object's new location in the frame.

``` swift
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
```

Use the observation’s [`boundingBox`](https://developer.apple.com/documentation/vision/vndetectedobjectobservation/2867227-boundingbox) to determine its location, so you can update your app or UI with the tracked object’s new location.  Also use it to seed the next round of tracking.

``` swift
inputObservations[observation.uuid] = observation
```

In practice, you should run a new tracking request with an updated set of input observations periodically to capture objects that were not present in your initial nomination frame. For instance, you could create a new [`VNTrackObjectRequest`](https://developer.apple.com/documentation/vision/vntrackobjectrequest) every ten frames.
