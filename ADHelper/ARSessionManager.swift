import ARKit
import SceneKit

protocol ARSessionManagerDelegate: AnyObject {
    func sessionManager(_ manager: ARSessionManager, didFailWithError error: Error)
    func sessionManager(_ manager: ARSessionManager, didUpdatePixelBuffer pixelBuffer: CVPixelBuffer, trackingState: ARCamera.TrackingState)
    func sessionManagerWasInterrupted(_ manager: ARSessionManager)
    func sessionManagerInterruptionEnded(_ manager: ARSessionManager)
}

class ARSessionManager: NSObject {
    private let sceneView: ARSCNView
    private var lastCameraPosition: simd_float4?
    private let minCameraMoveDistance: Float = 0.05 // 5厘米
    
    weak var delegate: ARSessionManagerDelegate?
    
    init(sceneView: ARSCNView) {
        self.sceneView = sceneView
        super.init()
        self.sceneView.session.delegate = self
    }
    
    func resetTracking() {
        guard ARWorldTrackingConfiguration.isSupported else {
            print("设备不支持 AR 世界追踪")
            return
        }
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        
        // 配置视频格式
        let availableFormats = ARWorldTrackingConfiguration.supportedVideoFormats
        if let bestFormat = availableFormats.first(where: { format in
            let resolution = format.imageResolution
            return resolution.width <= 1920
        }) ?? availableFormats.first {
            configuration.videoFormat = bestFormat
            print("已选择视频格式: \(bestFormat.imageResolution.width)x\(bestFormat.imageResolution.height)")
        }
        
        configuration.isLightEstimationEnabled = true
        configuration.isAutoFocusEnabled = true
        
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        print("AR会话已重置并应用新配置")
    }
    
    func pauseSession() {
        sceneView.session.pause()
    }
    
    func getCurrentFrame() -> ARFrame? {
        return sceneView.session.currentFrame
    }
    
    func getSceneView() -> ARSCNView {
        return sceneView
    }
}

extension ARSessionManager: ARSessionDelegate {
    func session(_ session: ARSession, didFailWithError error: Error) {
        delegate?.sessionManager(self, didFailWithError: error)
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        delegate?.sessionManagerWasInterrupted(self)
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        delegate?.sessionManagerInterruptionEnded(self)
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let cameraPosition = frame.camera.transform.columns.3
        if let last = lastCameraPosition {
            let dx = cameraPosition.x - last.x
            let dy = cameraPosition.y - last.y
            let dz = cameraPosition.z - last.z
            let distance = sqrt(dx*dx + dy*dy + dz*dz)
            if distance < minCameraMoveDistance {
                return
            }
        }
        lastCameraPosition = cameraPosition
        delegate?.sessionManager(self, didUpdatePixelBuffer: frame.capturedImage, trackingState: frame.camera.trackingState)
    }
} 