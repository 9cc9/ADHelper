import UIKit
import ARKit
import Vision
import SceneKit
import CoreML

class ARObjectDetectionViewController: UIViewController {
    
    private var sceneView: ARSCNView!
    private var visionRequests = [VNRequest]()
    private var detectedObjectAnnotations: [String: SCNNode] = [:]
    private var lastProcessedTime: TimeInterval = 0
    private let processingInterval: TimeInterval = 0.5 // 每0.5秒处理一次
    private var isProcessing = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupAR()
        setupVision()
        setupUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        resetTracking()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }
    
    private func resetTracking() {
        // 配置AR会话
        guard ARWorldTrackingConfiguration.isSupported else {
            print("设备不支持 AR 世界追踪")
            return
        }
        
        let configuration = ARWorldTrackingConfiguration()
        
        // 设置平面检测
        configuration.planeDetection = [.horizontal, .vertical]
        
        // 配置视频格式
        let availableFormats = ARWorldTrackingConfiguration.supportedVideoFormats
        if let bestFormat = availableFormats.first(where: { format in
            // 选择适中的分辨率
            let resolution = format.imageResolution
            return resolution.width <= 1920
        }) ?? availableFormats.first {
            configuration.videoFormat = bestFormat
            print("已选择视频格式: \(bestFormat.imageResolution.width)x\(bestFormat.imageResolution.height)")
        }
        
        // 启用自动光照估计
        configuration.isLightEstimationEnabled = true
        
        // 启用自动对焦
        configuration.isAutoFocusEnabled = true
        
        // 重置会话并应用新配置
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        
        print("AR会话已重置并应用新配置")
    }
    
    private func setupUI() {
        // 添加关闭按钮
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
    
    @objc private func closeTapped() {
        dismiss(animated: true)
    }
    
    private func setupAR() {
        // 设置AR场景视图
        sceneView = ARSCNView(frame: view.bounds)
        sceneView.delegate = self
        sceneView.session.delegate = self
        sceneView.autoenablesDefaultLighting = true
        view.addSubview(sceneView)
        
        // 配置场景
        let scene = SCNScene()
        sceneView.scene = scene
        
        // 添加调试选项
        #if DEBUG
        sceneView.debugOptions = [.showFeaturePoints, .showWorldOrigin]
        #endif
        
        // 设置场景视图的其他属性
        sceneView.automaticallyUpdatesLighting = true
        sceneView.antialiasingMode = .multisampling4X
    }
    
    private func setupVision() {
        guard let modelURL = Bundle.main.url(forResource: "Resnet50", withExtension: "mlmodelc") else {
            // 如果找不到模型文件，使用系统内置的图像分类模型
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
            // 如果加载失败，使用系统内置的图像分类模型
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
    
    private func processClassification(for request: VNRequest, error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                print("识别错误: \(error)")
                return
            }
            
            print("开始处理识别结果...")
            
            if let results = request.results as? [VNClassificationObservation] {
                print("获取到 \(results.count) 个识别结果")
                
                // 打印所有结果，包括低置信度的
                results.forEach { result in
                    print("识别到物体: \(result.identifier), 置信度: \(String(format: "%.2f%%", result.confidence * 100))")
                }
                
                // 只处理置信度大于50%的结果
                let highConfidenceResults = results.filter { $0.confidence > 0.5 }
                print("置信度大于50%的结果数量: \(highConfidenceResults.count)")
                
                // 清除所有现有标签
                self.detectedObjectAnnotations.values.forEach { $0.removeFromParentNode() }
                self.detectedObjectAnnotations.removeAll()
                
                // 为每个识别结果添加标签
                for (index, result) in highConfidenceResults.enumerated() {
                    let chineseLabel = self.getChineseLabel(for: result.identifier)
                    print("处理识别结果 \(index + 1): \(chineseLabel)")
                    
                    // 计算标签位置
                    let yOffset = CGFloat(index) * 0.1
                    let boundingBox = CGRect(x: 0.4, y: 0.4 + yOffset, width: 0.2, height: 0.2)
                    
                    self.addLabel(for: chineseLabel,
                                confidence: result.confidence,
                                at: boundingBox)
                }
            } else {
                print("未获取到有效的识别结果")
            }
        }
    }
    
    private func getChineseLabel(for identifier: String) -> String {
        // 扩展的中英文转换字典
        let translations = [
            "cup": "水杯",
            "bottle": "瓶子",
            "medicine": "药品",
            "pill bottle": "药瓶",
            "photo": "照片",
            "picture": "图片",
            "book": "书本",
            "phone": "手机",
            "computer": "电脑",
            "glasses": "眼镜",
            "medication": "药物",
            "tablet": "平板电脑",
            "remote": "遥控器",
            "key": "钥匙",
            "wallet": "钱包",
            "chair": "椅子",
            "table": "桌子",
            "lamp": "台灯",
            "clock": "时钟",
            "watch": "手表"
        ]
        
        // 处理复合词，如"pill_bottle"或"pill.bottle"
        let processedIdentifier = identifier.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
        
        return translations[processedIdentifier] ?? identifier
    }
    
    private func addLabel(for objectName: String, confidence: Float, at boundingBox: CGRect) {
        print("正在为物体 '\(objectName)' 创建标签")
        
        // 创建标签节点
        let labelNode = SCNNode()
        
        // 创建背景板
        let backgroundGeometry = SCNPlane(width: 0.2, height: 0.05)
        let backgroundMaterial = SCNMaterial()
        backgroundMaterial.diffuse.contents = UIColor.black.withAlphaComponent(0.7)
        backgroundGeometry.materials = [backgroundMaterial]
        let backgroundNode = SCNNode(geometry: backgroundGeometry)
        labelNode.addChildNode(backgroundNode)
        
        // 创建文本
        let confidenceString = String(format: "%.1f%%", confidence * 100)
        let text = SCNText(string: "\(objectName)", extrusionDepth: 0.001)
        text.font = UIFont.systemFont(ofSize: 0.03)
        text.firstMaterial?.diffuse.contents = UIColor.white
        text.firstMaterial?.isDoubleSided = true
        text.alignmentMode = CATextLayerAlignmentMode.center.rawValue
        text.truncationMode = CATextLayerTruncationMode.end.rawValue
        
        let textNode = SCNNode(geometry: text)
        // 调整文本位置使其居中
        let (min, max) = text.boundingBox
        let textWidth = max.x - min.x
        textNode.position = SCNVector3(-textWidth/2, -0.01, 0.001)
        labelNode.addChildNode(textNode)
        
        // 创建置信度文本
        let confidenceText = SCNText(string: confidenceString, extrusionDepth: 0.001)
        confidenceText.font = UIFont.systemFont(ofSize: 0.02)
        confidenceText.firstMaterial?.diffuse.contents = UIColor.lightGray
        confidenceText.firstMaterial?.isDoubleSided = true
        
        let confidenceNode = SCNNode(geometry: confidenceText)
        let (minConf, maxConf) = confidenceText.boundingBox
        let confidenceWidth = maxConf.x - minConf.x
        confidenceNode.position = SCNVector3(-confidenceWidth/2, -0.03, 0.001)
        labelNode.addChildNode(confidenceNode)
        
        // 获取屏幕中心点
        let screenCenter = CGPoint(x: boundingBox.midX * sceneView.bounds.width,
                                 y: boundingBox.midY * sceneView.bounds.height)
        
        // 进行射线检测
        let hitTestResults = sceneView.hitTest(screenCenter, types: [.featurePoint, .estimatedHorizontalPlane])
        
        if let hitResult = hitTestResults.first {
            // 设置标签位置
            let position = SCNVector3(
                hitResult.worldTransform.columns.3.x,
                hitResult.worldTransform.columns.3.y + 0.05, // 稍微上浮一点
                hitResult.worldTransform.columns.3.z
            )
            labelNode.position = position
            
            // 添加浮动动画
            let floatAnimation = SCNAction.sequence([
                SCNAction.moveBy(x: 0, y: 0.01, z: 0, duration: 1.0),
                SCNAction.moveBy(x: 0, y: -0.01, z: 0, duration: 1.0)
            ])
            labelNode.runAction(SCNAction.repeatForever(floatAnimation))
            
            // 始终面向相机
            let billboardConstraint = SCNBillboardConstraint()
            billboardConstraint.freeAxes = .Y
            labelNode.constraints = [billboardConstraint]
            
            // 移除旧标签
            detectedObjectAnnotations[objectName]?.removeFromParentNode()
            
            // 添加新标签
            sceneView.scene.rootNode.addChildNode(labelNode)
            detectedObjectAnnotations[objectName] = labelNode
            
            print("标签添加成功，位置: x=\(position.x), y=\(position.y), z=\(position.z)")
        } else {
            print("未能找到合适的位置放置标签")
        }
    }
}

// MARK: - ARSessionDelegate
extension ARObjectDetectionViewController: ARSessionDelegate {
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("AR会话错误: \(error.localizedDescription)")
        
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
        
        print("AR错误详情: \(errorMessage)")
        
        // 显示错误提示
        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: "AR会话错误",
                message: errorMessage,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "重试", style: .default) { [weak self] _ in
                self?.resetTracking()
            })
            alert.addAction(UIAlertAction(title: "关闭", style: .cancel) { [weak self] _ in
                self?.dismiss(animated: true)
            })
            self.present(alert, animated: true)
        }
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        print("AR会话被中断")
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        print("AR会话中断结束，重置跟踪")
        resetTracking()
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let currentTime = CACurrentMediaTime()
        
        // 避免重复处理和过于频繁的处理
        guard !isProcessing && currentTime - lastProcessedTime > processingInterval else { return }
        
        isProcessing = true
        lastProcessedTime = currentTime
        
        let pixelBuffer = frame.capturedImage
        
        // 确保图像质量
        guard frame.camera.trackingState == .normal else {
            isProcessing = false
            return
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                          orientation: .up,
                                          options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try handler.perform(self?.visionRequests ?? [])
            } catch {
                print("图像处理错误: \(error)")
            }
            self?.isProcessing = false
        }
    }
}

// MARK: - ARSCNViewDelegate
extension ARObjectDetectionViewController: ARSCNViewDelegate {
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            // 更新UI元素
            guard let self = self else { return }
            
            if let frame = self.sceneView.session.currentFrame {
                let camera = frame.camera
                if camera.trackingState != .normal {
                    print("相机跟踪状态: \(camera.trackingState)")
                }
            }
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        print("添加新锚点: \(type(of: anchor))")
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        // 处理锚点更新
    }
} 
