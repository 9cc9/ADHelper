//
//  ViewController.swift
//  ADHelper
//
//  Created by 贝贝 on 2025/4/23.
//

import UIKit

class ViewController: UIViewController {
    
    private lazy var arButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("物体识别", for: .normal)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 10
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(openARView), for: .touchUpInside)
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        view.backgroundColor = .white
        view.addSubview(arButton)
        
        NSLayoutConstraint.activate([
            arButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            arButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            arButton.widthAnchor.constraint(equalToConstant: 200),
            arButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    @objc private func openARView() {
        let arVC = ARObjectDetectionViewController()
        arVC.modalPresentationStyle = .fullScreen
        present(arVC, animated: true)
    }
}

