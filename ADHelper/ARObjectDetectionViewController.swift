import UIKit
import ARKit
import SceneKit

class ARObjectDetectionViewController: UIViewController {
    private var sceneView: ARSCNView!
    private var sessionManager: ARSessionManager!
    private var objectDetector: ObjectDetector!
    private var labelManager: ARLabelManager!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupAR()
        setupManagers()
        setupUI()
    }
    
    private func setupAR() {
        sceneView = ARSCNView(frame: view.bounds)
        sceneView.delegate = self
        sceneView.autoenablesDefaultLighting = true
        view.addSubview(sceneView)
        
        let scene = SCNScene()
        sceneView.scene = scene
        
        #if DEBUG
        sceneView.debugOptions = [.showFeaturePoints, .showWorldOrigin]
        #endif
        
        sceneView.automaticallyUpdatesLighting = true
        sceneView.antialiasingMode = .multisampling4X
    }
    
    private func setupManagers() {
        sessionManager = ARSessionManager(sceneView: sceneView)
        sessionManager.delegate = self
        
        objectDetector = ObjectDetector()
        objectDetector.delegate = self
        
        labelManager = ARLabelManager(sceneView: sceneView)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        sceneView.addGestureRecognizer(tapGesture)
    }
    
    private func setupUI() {
        let closeButton = UIButton(type: .system)
        closeButton.setTitle("关闭", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        closeButton.layer.cornerRadius = 8
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(closeButton)
        
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 60),
            closeButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionManager.resetTracking()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionManager.pauseSession()
    }
    
    @objc private func closeTapped() {
        dismiss(animated: true)
    }
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: sceneView)
        let hitResults = sceneView.hitTest(location, options: nil)
        
        if let node = hitResults.first?.node,
           let objectID = findObjectID(for: node) {
            promptForCustomName(objectID: objectID)
        }
    }
    
    private func findObjectID(for node: SCNNode) -> String? {
        var current: SCNNode? = node
        while current != nil {
            if let name = current?.name {
                return name
            }
            current = current?.parent
        }
        return nil
    }
    
    private func promptForCustomName(objectID: String) {
        let alert = UIAlertController(title: "自定义标签", message: "请输入新名称", preferredStyle: .alert)
        alert.addTextField { [weak self] textField in
            textField.placeholder = "输入新名称"
            textField.text = self?.labelManager.getCustomName(for: objectID)
        }
        
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self] _ in
            if let name = alert.textFields?.first?.text {
                self?.labelManager.saveCustomName(name, for: objectID)
                self?.labelManager.refreshLabel(for: objectID)
            }
        })
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
}

extension ARObjectDetectionViewController: ARSessionManagerDelegate {
    func sessionManager(_ manager: ARSessionManager, didFailWithError error: Error) {
        guard let arError = error as? ARError else { return }
        
        let errorMessage: String
        switch arError.code {
        case .cameraUnauthorized:
            errorMessage = "请在设置中允许访问相机"
        case .sensorUnavailable:
            errorMessage = "传感器不可用，请确保设备支持AR"
        case .sensorFailed:
            errorMessage = "传感器出错，请重启应用"
        case .worldTrackingFailed:
            errorMessage = "跟踪失败，请尝试重置"
        default:
            errorMessage = "出现未知错误: \(error.localizedDescription)"
        }
        
        let alert = UIAlertController(
            title: "AR会话错误",
            message: errorMessage,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "重试", style: .default) { [weak self] _ in
            self?.sessionManager.resetTracking()
        })
        alert.addAction(UIAlertAction(title: "关闭", style: .cancel) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }
    
    func sessionManager(_ manager: ARSessionManager, didUpdate frame: ARFrame) {
        objectDetector.processFrame(frame.capturedImage, trackingState: frame.camera.trackingState)
    }
    
    func sessionManagerWasInterrupted(_ manager: ARSessionManager) {
        print("AR会话被中断")
    }
    
    func sessionManagerInterruptionEnded(_ manager: ARSessionManager) {
        print("AR会话中断结束，重置跟踪")
        sessionManager.resetTracking()
    }
}

extension ARObjectDetectionViewController: ObjectDetectorDelegate {
    func objectDetector(_ detector: ObjectDetector, didDetectObjects results: [VNClassificationObservation]) {
        labelManager.clearAllLabels()
        
        for (index, result) in results.enumerated() {
            let yOffset = CGFloat(index) * 0.1
            let boundingBox = CGRect(x: 0.4, y: 0.4 + yOffset, width: 0.2, height: 0.2)
            labelManager.addLabel(for: result.identifier,
                                confidence: result.confidence,
                                at: boundingBox)
        }
    }
    
    func objectDetector(_ detector: ObjectDetector, didFailWithError error: Error) {
        print("物体识别错误: \(error)")
    }
}

extension ARObjectDetectionViewController: ARSCNViewDelegate {
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if let frame = sceneView.session.currentFrame {
            let camera = frame.camera
            if camera.trackingState != .normal {
                print("相机跟踪状态: \(camera.trackingState)")
            }
        }
    }
} 