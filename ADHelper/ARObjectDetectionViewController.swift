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
        
        // 验证文本内容
        guard !objectName.isEmpty else {
            print("错误：物体名称为空")
            return
        }
        
        // 创建标签节点
        let labelNode = SCNNode()
        
        // 创建背景板
        let backgroundGeometry = SCNPlane(width: 0.12, height: 0.06) // 增大背景板尺寸
        let backgroundMaterial = SCNMaterial()
        backgroundMaterial.diffuse.contents = UIColor.black.withAlphaComponent(0.7)
        backgroundGeometry.materials = [backgroundMaterial]
        let backgroundNode = SCNNode(geometry: backgroundGeometry)
        labelNode.addChildNode(backgroundNode)
        
        // 创建物体名称文本
        let displayName = getDisplayName(for: objectName)
        print("处理后的显示文本: '\(displayName)'")
        let nameText = createSafeText(displayName, size: 24)
        
        guard let nameNode = createTextNode(from: nameText) else {
            print("错误：无法创建名称文本节点")
            return
        }
        nameNode.position.y = 0.01 // 调整位置
        labelNode.addChildNode(nameNode)
        
        // 创建置信度文本
        let confidenceString = String(format: "%.1f%%", confidence * 100)
        if let confidenceNode = createConfidenceNode(confidenceString) {
            confidenceNode.position.y = -0.01 // 调整位置
            labelNode.addChildNode(confidenceNode)
        }
        
        // 获取屏幕中心点
        let screenCenter = CGPoint(x: boundingBox.midX * sceneView.bounds.width,
                                 y: boundingBox.midY * sceneView.bounds.height)
        
        // 进行射线检测
        var hitTestResults = sceneView.hitTest(screenCenter, types: [.featurePoint])
        if hitTestResults.isEmpty {
            hitTestResults = sceneView.hitTest(screenCenter, types: [.estimatedHorizontalPlane])
        }
        
        if let hitResult = hitTestResults.first {
            let position = SCNVector3(
                hitResult.worldTransform.columns.3.x,
                hitResult.worldTransform.columns.3.y + 0.05,
                hitResult.worldTransform.columns.3.z
            )
            labelNode.position = position
            
            // 添加浮动动画
            addFloatingAnimation(to: labelNode)
            
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
    
    private func getDisplayName(for identifier: String) -> String {
        // 处理原始标识符
        let processedName = identifier
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        
        // 扩展翻译字典
        let translations = [
            "structure": "结构",
            "wood": "木材",
            "processed": "加工",
            "wood processed": "加工木材",
            "table": "桌子",
            "chair": "椅子",
            "desk": "书桌",
            "cabinet": "柜子",
            "shelf": "架子",
            "door": "门",
            "window": "窗户",
            "floor": "地板",
            "wall": "墙壁",
            "ceiling": "天花板",
            "light": "灯",
            "lamp": "台灯",
            "computer": "电脑",
            "monitor": "显示器",
            "keyboard": "键盘",
            "mouse": "鼠标",
            "phone": "手机",
            "book": "书本",
            "paper": "纸张",
            "pen": "笔",
            "cup": "水杯",
            "bottle": "瓶子",
            "glass": "玻璃杯",
            "plate": "盘子",
            "bowl": "碗",
            "furniture": "家具",
            "electronic": "电子设备",
            "device": "设备",
            "metal": "金属",
            "plastic": "塑料",
            "wooden": "木制",
            "steel": "钢制",
            "aluminum": "铝制"
        ]
        
        // 尝试直接匹配
        if let translation = translations[processedName.lowercased()] {
            return translation
        }
        
        // 如果是复合词，尝试翻译各个部分
        let words = processedName.lowercased().split(separator: " ")
        let translatedWords = words.map { word -> String in
            if let translation = translations[String(word)] {
                return translation
            }
            return String(word)
        }
        
        let result = translatedWords.joined(separator: "")
        print("翻译结果: '\(processedName)' -> '\(result)'")
        return result
    }
    
    private func createSafeText(_ string: String, size: CGFloat) -> SCNText {
        // 确保字符串不为空
        let safeString = string.isEmpty ? "未知物体" : string
        
        // 创建2D文本来预计算尺寸
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size, weight: .medium)
        ]
        let textSize = (safeString as NSString).size(withAttributes: attributes)
        
        // 创建文本几何体
        let text = SCNText(string: safeString, extrusionDepth: 0.01)
        
        // 设置字体
        text.font = UIFont.systemFont(ofSize: size, weight: .medium)
        
        // 设置文本属性
        text.flatness = 0.2
        text.chamferRadius = 0.0
        
        // 确保文本有合适的容器大小
        text.containerFrame = CGRect(x: 0, y: 0, width: max(textSize.width, 1), height: max(textSize.height, 1))
        
        // 设置材质
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.white
        material.isDoubleSided = true
        text.materials = [material]
        
        return text
    }
    
    private func createTextNode(from text: SCNText) -> SCNNode? {
        let textNode = SCNNode(geometry: text)
        
        // 使用文本的容器框架计算尺寸
        let width = CGFloat(text.containerFrame.width)
        let height = CGFloat(text.containerFrame.height)
        
        // 验证尺寸
        guard width > 0, height > 0 else {
            print("错误：文本尺寸无效 - 宽度: \(width), 高度: \(height)")
            return nil
        }
        
        // 调整位置和缩放
        let scale: Float = 0.0003
        textNode.scale = SCNVector3(scale, scale, scale)
        textNode.position = SCNVector3(-Float(width) * scale / 2, 0, 0.001)
        
        return textNode
    }
    
    private func createConfidenceNode(_ confidenceString: String) -> SCNNode? {
        let confidenceText = createSafeText(confidenceString, size: 40) // 增大字体大小
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.lightGray
        material.isDoubleSided = true
        confidenceText.materials = [material]
        
        guard let confidenceNode = createTextNode(from: confidenceText) else {
            print("错误：无法创建置信度节点")
            return nil
        }
        
        confidenceNode.position.y = -0.02
        return confidenceNode
    }
    
    private func addFloatingAnimation(to node: SCNNode) {
        let floatAnimation = SCNAction.sequence([
            SCNAction.moveBy(x: 0, y: 0.005, z: 0, duration: 1.0),
            SCNAction.moveBy(x: 0, y: -0.005, z: 0, duration: 1.0)
        ])
        node.runAction(SCNAction.repeatForever(floatAnimation))
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
