import ARKit
import RealityKit
import SwiftUI

@Observable
@MainActor
class ViewModel {
    let session = ARKitSession()
    let handTracking = HandTrackingProvider()
    let sceneReconstruction = SceneReconstructionProvider()
    
    private var meshEntities = [UUID: ModelEntity]()
    var contentEntity = Entity()
    var latestHandTracking: HandsUpdates = .init(left: nil, right: nil)
    var leftHandEntity = Entity()
    var rightHandEntity = Entity()
    
    struct HandsUpdates {
        var left: HandAnchor?
        var right: HandAnchor?
    }
    
    var errorState = false
    
    func setupContentEntity() -> Entity {
        return contentEntity
    }
    
    var dataProvidersAreSupported: Bool {
        HandTrackingProvider.isSupported && SceneReconstructionProvider.isSupported
    }
    
    var isReadyToRun: Bool {
        handTracking.state == .initialized && sceneReconstruction.state == .initialized
    }
    
    func processHandUpdates() async {
        for await update in handTracking.anchorUpdates {
            switch update.event {
            case .updated:
                let anchor = update.anchor
                
                guard anchor.isTracked else { continue }
                
                if anchor.chirality == .left {
                    latestHandTracking.left = anchor
                    spawnSphereOnGunGesture(handAnchor: latestHandTracking.left)
                } else if anchor.chirality == .right {
                    latestHandTracking.right = anchor
                    spawnSphereOnGunGesture(handAnchor: latestHandTracking.right)
                }
            default:
                break
            }
        }
    }
    
    // 銃を撃つポーズの計算
    func detectGunGestureTransform(handAnchor: HandAnchor?) -> simd_float4x4? {
        guard let handAnchor = handAnchor else { return nil }
        guard
            let handThumbTip = handAnchor.handSkeleton?.joint(.thumbTip),
            let handIndexFingerKnuckle = handAnchor.handSkeleton?.joint(.indexFingerKnuckle),
            handThumbTip.isTracked &&
                handIndexFingerKnuckle.isTracked
        else {
            return nil
        }
        
        let originFromHandThumbTipTransform = matrix_multiply(
            handAnchor.originFromAnchorTransform, handThumbTip.anchorFromJointTransform
        ).columns.3.xyz
        
        let originFromHandIndexFingerKnuckleTransform = matrix_multiply(
            handAnchor.originFromAnchorTransform, handIndexFingerKnuckle.anchorFromJointTransform
        ).columns.3.xyz
        
        let thumbToIndexFingerDistance = distance(
            originFromHandThumbTipTransform,
            originFromHandIndexFingerKnuckleTransform
        )
        
        // 親指と人差し指の根本が接触しているか判断
        if thumbToIndexFingerDistance < 0.04 { // 接触していると見なす距離の閾値
            return handAnchor.originFromAnchorTransform
        } else {
            return nil
        }
    }
    
    func processReconstructionUpdates() async {
        for await update in sceneReconstruction.anchorUpdates {
            let meshAnchor = update.anchor
            
            guard let shape = try? await ShapeResource.generateStaticMesh(from: meshAnchor) else { continue }
            switch update.event {
            case .added:
                let entity = ModelEntity()
                entity.transform = Transform(matrix: meshAnchor.originFromAnchorTransform)
                entity.collision = CollisionComponent(shapes: [shape], isStatic: true)
                entity.components.set(InputTargetComponent())
                
                entity.physicsBody = PhysicsBodyComponent(mode: .static)
                
                meshEntities[meshAnchor.id] = entity
                contentEntity.addChild(entity)
            case .updated:
                guard let entity = meshEntities[meshAnchor.id] else { continue }
                entity.transform = Transform(matrix: meshAnchor.originFromAnchorTransform)
                entity.collision?.shapes = [shape]
            case .removed:
                meshEntities[meshAnchor.id]?.removeFromParent()
                meshEntities.removeValue(forKey: meshAnchor.id)
            }
        }
    }
    
    func monitorSessionEvents() async {
        for await event in session.events {
            switch event {
            case .authorizationChanged(type: _, status: let status):
                print("Authorization changed to: \(status)")
                
                if status == .denied {
                    errorState = true
                }
            case .dataProviderStateChanged(dataProviders: let providers, newState: let state, error: let error):
                print("Data provider changed: \(providers), \(state)")
                if let error {
                    print("Data provider reached an error state: \(error)")
                    errorState = true
                }
            @unknown default:
                fatalError("Unhandled new event type \(event)")
            }
        }
    }
    
    func spawnSphereOnGunGesture(handAnchor: HandAnchor?) {
        guard let handAnchor = handAnchor,
              let handLocation = detectGunGestureTransform(handAnchor: handAnchor) else { return }
        // 球体のModelEntity
        let entity = ModelEntity(
            mesh: .generateSphere(radius: 0.05),
            materials: [SimpleMaterial(color: .white, isMetallic: true)],
            collisionShape: .generateSphere(radius: 0.05),
            mass: 1.0
        )
        
        // 球体を生成する位置
        entity.transform.translation = Transform(matrix: handLocation).translation + calculateTranslationOffset(handAnchor: handAnchor)
        // 球体を飛ばす方向
        let forceDirection = calculateForceDirection(handAnchor: handAnchor)
        entity.addForce(forceDirection * 300, relativeTo: nil)
        // 球体をcontentEntityの子として追加
        contentEntity.addChild(entity)
    }
    
    // 指の長さに相当するoffsetを定義
    func calculateTranslationOffset(handAnchor: HandAnchor) -> SIMD3<Float> {
        let handRotation = Transform(matrix: handAnchor.originFromAnchorTransform).rotation
        return handRotation.act(handAnchor.chirality == .left ? SIMD3(0.25, 0, 0) : SIMD3(-0.25, 0, 0))
    }
    
    // 手の向きに基づいて力を加える方向を計算
    func calculateForceDirection(handAnchor: HandAnchor) -> SIMD3<Float> {
        let handRotation = Transform(matrix: handAnchor.originFromAnchorTransform).rotation
        return handRotation.act(handAnchor.chirality == .left ? SIMD3(1, 0, 0) : SIMD3(-1, 0, 0))
    }
}
