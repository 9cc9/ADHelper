import SceneKit
import ARKit

class ARLabelManager {
    private var detectedObjectAnnotations: [String: SCNNode] = [:]
    private let sceneView: ARSCNView
    
    init(sceneView: ARSCNView) {
        self.sceneView = sceneView
    }
    
    func addLabel(for objectName: String, confidence: Float, at boundingBox: CGRect) {
        guard !objectName.isEmpty else { return }
        
        let labelNode = createLabelNode(objectName: objectName, confidence: confidence)
        let screenCenter = CGPoint(x: boundingBox.midX * sceneView.bounds.width,
                                 y: boundingBox.midY * sceneView.bounds.height)
        
        if let position = findLabelPosition(at: screenCenter) {
            placeLabel(labelNode, at: position, objectID: objectName)
        }
    }
    
    private func createLabelNode(objectName: String, confidence: Float) -> SCNNode {
        let labelNode = SCNNode()
        
        // 创建背景
        let backgroundGeometry = SCNPlane(width: 0.12, height: 0.06)
        let backgroundMaterial = SCNMaterial()
        backgroundMaterial.diffuse.contents = UIColor.black.withAlphaComponent(0.7)
        backgroundGeometry.materials = [backgroundMaterial]
        let backgroundNode = SCNNode(geometry: backgroundGeometry)
        labelNode.addChildNode(backgroundNode)
        
        // 添加文本
        let displayName = getCustomName(for: objectName) ?? objectName
        if let nameNode = createTextNode(text: displayName, size: 24) {
            nameNode.position.y = 0.01
            labelNode.addChildNode(nameNode)
        }
        
        // 添加置信度
        let confidenceString = String(format: "%.1f%%", confidence * 100)
        if let confidenceNode = createTextNode(text: confidenceString, size: 40, color: .lightGray) {
            confidenceNode.position.y = -0.01
            labelNode.addChildNode(confidenceNode)
        }
        
        return labelNode
    }
    
    private func createTextNode(text: String, size: CGFloat, color: UIColor = .white) -> SCNNode? {
        let textGeometry = SCNText(string: text, extrusionDepth: 0.01)
        textGeometry.font = UIFont.systemFont(ofSize: size, weight: .medium)
        textGeometry.flatness = 0.2
        
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.isDoubleSided = true
        textGeometry.materials = [material]
        
        let textNode = SCNNode(geometry: textGeometry)
        let scale: Float = 0.0003
        textNode.scale = SCNVector3(scale, scale, scale)
        
        return textNode
    }
    
    private func findLabelPosition(at screenPoint: CGPoint) -> SCNVector3? {
        var hitTestResults = sceneView.hitTest(screenPoint, types: [.featurePoint])
        if hitTestResults.isEmpty {
            hitTestResults = sceneView.hitTest(screenPoint, types: [.estimatedHorizontalPlane])
        }
        
        if let hitResult = hitTestResults.first {
            return SCNVector3(
                hitResult.worldTransform.columns.3.x,
                hitResult.worldTransform.columns.3.y + 0.05,
                hitResult.worldTransform.columns.3.z
            )
        }
        return nil
    }
    
    private func placeLabel(_ labelNode: SCNNode, at position: SCNVector3, objectID: String) {
        labelNode.position = position
        addFloatingAnimation(to: labelNode)
        
        let billboardConstraint = SCNBillboardConstraint()
        billboardConstraint.freeAxes = .Y
        labelNode.constraints = [billboardConstraint]
        
        labelNode.name = objectID
        detectedObjectAnnotations[objectID]?.removeFromParentNode()
        sceneView.scene.rootNode.addChildNode(labelNode)
        detectedObjectAnnotations[objectID] = labelNode
    }
    
    private func addFloatingAnimation(to node: SCNNode) {
        let floatAnimation = SCNAction.sequence([
            SCNAction.moveBy(x: 0, y: 0.005, z: 0, duration: 1.0),
            SCNAction.moveBy(x: 0, y: -0.005, z: 0, duration: 1.0)
        ])
        node.runAction(SCNAction.repeatForever(floatAnimation))
    }
    
    func clearAllLabels() {
        detectedObjectAnnotations.values.forEach { $0.removeFromParentNode() }
        detectedObjectAnnotations.removeAll()
    }
    
    func getCustomName(for objectID: String) -> String? {
        let customNames = UserDefaults.standard.dictionary(forKey: "CustomObjectNames") as? [String: String]
        return customNames?[objectID]
    }
    
    func saveCustomName(_ name: String, for objectID: String) {
        var customNames = UserDefaults.standard.dictionary(forKey: "CustomObjectNames") as? [String: String] ?? [:]
        customNames[objectID] = name
        UserDefaults.standard.set(customNames, forKey: "CustomObjectNames")
    }
    
    func refreshLabel(for objectID: String) {
        if let node = detectedObjectAnnotations[objectID] {
            node.removeFromParentNode()
            detectedObjectAnnotations.removeValue(forKey: objectID)
        }
        let boundingBox = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        addLabel(for: objectID, confidence: 1.0, at: boundingBox)
    }
} 