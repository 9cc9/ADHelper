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
        let modelURL = Bundle.main.url(forResource: "Inceptionv3", withExtension: "mlmodelc")
        if modelURL == nil {
            print("1.无法加载Resnet50模型")

            if let resourcePath = Bundle.main.resourcePath {
                do {
                    let files = try FileManager.default.contentsOfDirectory(atPath: resourcePath)
                    print("Bundle.main.resourcePath 文件列表：\n\(files.joined(separator: "\n"))")
                } catch {
                    print("无法获取Bundle资源文件列表: \(error)")
                }
            }
            setupDefaultVision()
            return
        }
        
        do {
            let visionModel = try VNCoreMLModel(for: MLModel(contentsOf: modelURL!))
            let request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
                self?.processClassification(for: request, error: error)
            }
            request.imageCropAndScaleOption = .centerCrop
            visionRequests = [request]
        } catch {
            print("2.无法加载DETRResnet50SemanticSegmentationF16模型: \(error)")
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
        
        // 临时注释掉 trackingState 判断
        // guard trackingState == .normal else {
        //     print("[LOG] 相机跟踪状态异常: \(trackingState)")
        //     return
        // }
        
        isProcessing = true
        lastProcessedTime = currentTime
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                          orientation: .up,
                                          options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try handler.perform(self?.visionRequests ?? [])
            } catch {
                // delegate回调放到主线程，避免UI线程警告
                DispatchQueue.main.async {
                    self?.delegate?.objectDetector(self!, didFailWithError: error)
                }
            }
            // isProcessing 状态更新也放到主线程，避免潜在线程安全问题
            DispatchQueue.main.async {
                self?.isProcessing = false
            }
        }
    }
    
    private func processClassification(for request: VNRequest, error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.delegate?.objectDetector(self, didFailWithError: error)
            }
            return
        }
        
        if let results = request.results as? [VNClassificationObservation] {
            let highConfidenceResults = results.filter { $0.confidence > 0.3 }
            
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
            // delegate回调放到主线程，避免UI线程警告
            DispatchQueue.main.async {
                self.delegate?.objectDetector(self, didDetectObjects: finalResults)
            }
        }
    }
} 
