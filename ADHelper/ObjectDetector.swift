import Vision
import CoreML
import UIKit
import ARKit 

protocol ObjectDetectorDelegate: AnyObject {
    func objectDetector(_ detector: ObjectDetector, didDetectObjects results: [VNClassificationObservation])
    func objectDetector(_ detector: ObjectDetector, didFailWithError error: Error)
}

class ObjectDetector {
    private var visionRequests = [VNRequest]()
    private var isProcessing = false
    private var lastProcessedTime: TimeInterval = 0
    private let processingInterval: TimeInterval = 0.5
    
    weak var delegate: ObjectDetectorDelegate?
    
    init() {
        setupVision()
    }
    
    private func setupVision() {
        guard let modelURL = Bundle.main.url(forResource: "Resnet50", withExtension: "mlmodelc") else {
            setupDefaultVision()
            return
        }
        
        do {
            let visionModel = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
            let request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
                self?.processClassification(for: request, error: error)
            }
            request.imageCropAndScaleOption = .centerCrop
            visionRequests = [request]
        } catch {
            print("无法加载ResNet50模型: \(error)")
            setupDefaultVision()
        }
    }
    
    private func setupDefaultVision() {
        if let request = try? VNClassifyImageRequest(completionHandler: { [weak self] request, error in
            self?.processClassification(for: request, error: error)
        }) {
            visionRequests = [request]
        }
    }
    
    func processFrame(_ pixelBuffer: CVPixelBuffer, trackingState: ARCamera.TrackingState) {
        let currentTime = CACurrentMediaTime()
        
        guard !isProcessing && currentTime - lastProcessedTime > processingInterval else {
            return
        }
        
        guard trackingState == .normal else {
            print("[LOG] 相机跟踪状态异常: \(trackingState)")
            return
        }
        
        isProcessing = true
        lastProcessedTime = currentTime
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                          orientation: .up,
                                          options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try handler.perform(self?.visionRequests ?? [])
            } catch {
                self?.delegate?.objectDetector(self!, didFailWithError: error)
            }
            self?.isProcessing = false
        }
    }
    
    private func processClassification(for request: VNRequest, error: Error?) {
        if let error = error {
            delegate?.objectDetector(self, didFailWithError: error)
            return
        }
        
        if let results = request.results as? [VNClassificationObservation] {
            let highConfidenceResults = results.filter { $0.confidence > 0.5 }
            
            // 针对同一物体，只保留置信度最高的结果
            var bestResults: [String: VNClassificationObservation] = [:]
            for result in highConfidenceResults {
                let key = result.identifier
                if let existing = bestResults[key] {
                    if result.confidence > existing.confidence {
                        bestResults[key] = result
                    }
                } else {
                    bestResults[key] = result
                }
            }
            
            let finalResults = Array(bestResults.values)
            delegate?.objectDetector(self, didDetectObjects: finalResults)
        }
    }
} 