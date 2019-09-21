//
//  ViewController.swift
//  DetectRectangles
//
//  Created by Bellergy on 21/9/2019.
//  Copyright © 2019 Design Quest Limited. All rights reserved.
//

import UIKit
import AVFoundation
import Vision

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    // MARK: - Properties
    
    var session = AVCaptureSession()
    var requests = [VNRequest]()
    
    // MARK: - Config
    
    var sessionPreset = AVCaptureSession.Preset.high // change the capture quality here
    var maximumObservations = 0 // Allows Vision algorithms to return the number of observations.
    var minimumSize:Float = 0.1 // the minimum size of the rectangle to be detected (0 - 1)
    
    // MARK - Outlets
    
    @IBOutlet weak var videoImageView: UIImageView!
    @IBOutlet weak var infoView: UIView!
    
    // MARK: - Override
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startLiveVideo()
        startDetection()
    }
    
    // MARK: - Delegate
    
    // AVCaptureVideoDataOutputSampleBufferDelegate
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        var requestOptions:[VNImageOption : Any] = [:]
        if let camData = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil) {
            requestOptions = [.cameraIntrinsics:camData]
        }
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: CGImagePropertyOrientation.right, options: requestOptions)
        do {
            try imageRequestHandler.perform(self.requests) // pass the analysis requests here
        } catch {
            print(error)
        }
    }
    
    // MARK: - Video session
    
    private func startLiveVideo() {
        if (!session.isRunning) {
            session.sessionPreset = self.sessionPreset
            let captureDevice = AVCaptureDevice.default(for: AVMediaType.video)
            let deviceInput = try! AVCaptureDeviceInput(device: captureDevice!)
            let deviceOutput = AVCaptureVideoDataOutput()
            deviceOutput.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: DispatchQoS.QoSClass.default))
            session.addInput(deviceInput)
            session.addOutput(deviceOutput)
            let videoLayer = AVCaptureVideoPreviewLayer(session: session)
            videoLayer.frame = videoImageView.bounds
            videoImageView.layer.addSublayer(videoLayer)
            session.startRunning()
        }
    }
    
    // MARK: - Detection
    
    private func startDetection() {
        let request = VNDetectRectanglesRequest(completionHandler: self.detectionHandler)
        request.maximumObservations = self.maximumObservations
        request.minimumSize = self.minimumSize
        self.requests = [request]
    }
    
    private func detectionHandler(request: VNRequest, error: Error?) {
        guard let results = request.results else { return }
        let observations = results.map({$0 as! VNRectangleObservation})
        DispatchQueue.main.async() {
            let frame = self.infoView.bounds
            
            // Remove all layers
            self.infoView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
            
            // Draw the frames and add them to infoView
            for ov in observations {
                let layer = self.drawFrame(observation: ov, frame: frame)
                self.infoView.layer.addSublayer(layer)
            }
        }
    }
    
    private func drawFrame(observation ov:VNRectangleObservation, frame: CGRect) -> CAShapeLayer {
        let rectangle = UIBezierPath()
        rectangle.move(to: CGPoint(x: frame.width  * ov.topLeft.x, y: frame.height * (1-ov.topLeft.y)))
        rectangle.addLine(to: CGPoint(x: frame.width * ov.topRight.x, y: frame.height * (1-ov.topRight.y)))
        rectangle.addLine(to: CGPoint(x: frame.width * ov.bottomRight.x, y: frame.height * (1-ov.bottomRight.y)))
        rectangle.addLine(to: CGPoint(x: frame.width * ov.bottomLeft.x, y: frame.height * (1-ov.bottomLeft.y)))
        rectangle.close()
        let rec = CAShapeLayer()
        rec.path = rectangle.cgPath
        rec.fillColor = UIColor.red.cgColor
        rec.opacity = 0.3
        return rec
    }

}
