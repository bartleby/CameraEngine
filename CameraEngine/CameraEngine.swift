//
//  CameraEngine.swift
//  CameraEngine2
//
//  Created by Remi Robert on 24/12/15.
//  Copyright © 2015 Remi Robert. All rights reserved.
//

import UIKit
import AVFoundation

public enum CameraEngineSessionPreset {
    case photo
    case high
    case medium
    case low
    case res352x288
    case res640x480
    case res1280x720
    case res1920x1080
    case res3840x2160
    case frame960x540
    case frame1280x720
    case inputPriority
    
    public func foundationPreset() -> String {
        switch self {
        case .photo: return AVCaptureSession.Preset.photo.rawValue
        case .high: return AVCaptureSession.Preset.high.rawValue
        case .medium: return AVCaptureSession.Preset.medium.rawValue
        case .low: return AVCaptureSession.Preset.low.rawValue
        case .res352x288: return AVCaptureSession.Preset.cif352x288.rawValue
        case .res640x480: return AVCaptureSession.Preset.vga640x480.rawValue
        case .res1280x720: return AVCaptureSession.Preset.hd1280x720.rawValue
        case .res1920x1080: return AVCaptureSession.Preset.hd1920x1080.rawValue
        case .res3840x2160:
            if #available(iOS 9.0, *) {
                return AVCaptureSession.Preset.hd4K3840x2160.rawValue
            }
            else {
                return AVCaptureSession.Preset.photo.rawValue
            }
        case .frame960x540: return AVCaptureSession.Preset.iFrame960x540.rawValue
        case .frame1280x720: return AVCaptureSession.Preset.iFrame1280x720.rawValue
        default: return AVCaptureSession.Preset.photo.rawValue
        }
    }
    
    public static func availablePresset() -> [CameraEngineSessionPreset] {
        return [
            .photo,
            .high,
            .medium,
            .low,
            .res352x288,
            .res640x480,
            .res1280x720,
            .res1920x1080,
            .res3840x2160,
            .frame960x540,
            .frame1280x720,
            .inputPriority
        ]
    }
}

let cameraEngineSessionQueueIdentifier = "com.cameraEngine.capturesession"

public class CameraEngine: NSObject {
    
    let session = AVCaptureSession()
    let cameraDevice = CameraEngineDevice()
    let cameraOutput = CameraEngineCaptureOutput()
    let cameraInput = CameraEngineDeviceInput()
    let cameraMetadata = CameraEngineMetadataOutput()
    let cameraGifEncoder = CameraEngineGifEncoder()
    let capturePhotoSettings = AVCapturePhotoSettings()
    var captureDeviceIntput: AVCaptureDeviceInput?
    
    var sessionQueue: DispatchQueue = DispatchQueue(label: cameraEngineSessionQueueIdentifier)
    
    private var _torchMode: AVCaptureDevice.TorchMode = .off
    public var torchMode: AVCaptureDevice.TorchMode! {
        get {
            return _torchMode
        }
        set {
            _torchMode = newValue
            configureTorch(newValue)
        }
    }
    
    private var _flashMode: AVCaptureDevice.FlashMode = .off
    public var flashMode: AVCaptureDevice.FlashMode! {
        get {
            return _flashMode
        }
        set {
            _flashMode = newValue
            configureFlash(newValue)
        }
    }
    
    public lazy var previewLayer: AVCaptureVideoPreviewLayer! = {
        let layer =  AVCaptureVideoPreviewLayer(session: self.session)
        layer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        return layer
    }()
    
    private var _sessionPresset: CameraEngineSessionPreset = .inputPriority
    public var sessionPresset: CameraEngineSessionPreset! {
        get {
            return self._sessionPresset
        }
        set {
            if self.session.canSetSessionPreset(AVCaptureSession.Preset(rawValue: newValue.foundationPreset())) {
                self._sessionPresset = newValue
                self.session.sessionPreset = AVCaptureSession.Preset(rawValue: self._sessionPresset.foundationPreset())
            }
            else {
                fatalError("[CameraEngine] session presset : [\(newValue.foundationPreset())] uncompatible with the current device")
            }
        }
    }
    
    private var _cameraFocus: CameraEngineCameraFocus = .continuousAutoFocus
    public var cameraFocus: CameraEngineCameraFocus! {
        get {
            return self._cameraFocus
        }
        set {
            self.cameraDevice.changeCameraFocusMode(newValue)
            self._cameraFocus = newValue
        }
    }
    
    private var _metadataDetection: CameraEngineCaptureOutputDetection = .none
    public var metadataDetection: CameraEngineCaptureOutputDetection! {
        get {
            return self._metadataDetection
        }
        set {
            self._metadataDetection = newValue
            self.cameraMetadata.configureMetadataOutput(self.session, sessionQueue: self.sessionQueue, metadataType: self._metadataDetection)
        }
    }
    
    private var _videoEncoderPresset: CameraEngineVideoEncoderEncoderSettings!
    public var videoEncoderPresset: CameraEngineVideoEncoderEncoderSettings! {
        set {
            self._videoEncoderPresset = newValue
            self.cameraOutput.setPressetVideoEncoder(self._videoEncoderPresset)
        }
        get {
            return self._videoEncoderPresset
        }
    }
    
    private var _cameraZoomFactor: CGFloat = 1.0
    public var cameraZoomFactor: CGFloat! {
        get {
            if let `captureDevice` = captureDevice {
                _cameraZoomFactor = captureDevice.videoZoomFactor
            }
            
            return self._cameraZoomFactor
        }
        set {
            let newZoomFactor = self.cameraDevice.changeCurrentZoomFactor(newValue)
            if newZoomFactor > 0 {
                self._cameraZoomFactor = newZoomFactor
            }
        }
    }
    
    public var blockCompletionBuffer: blockCompletionOutputBuffer? {
        didSet {
            self.cameraOutput.blockCompletionBuffer = self.blockCompletionBuffer
        }
    }
    
    public var blockCompletionProgress: blockCompletionProgressRecording? {
        didSet {
            self.cameraOutput.blockCompletionProgress = self.blockCompletionProgress
        }
    }
    
    public var blockCompletionFaceDetection: blockCompletionDetectionFace? {
        didSet {
            self.cameraMetadata.blockCompletionFaceDetection = self.blockCompletionFaceDetection
        }
    }
    
    public var blockCompletionCodeDetection: blockCompletionDetectionCode? {
        didSet {
            self.cameraMetadata.blockCompletionCodeDetection = self.blockCompletionCodeDetection
        }
    }
    
    private var _rotationCamera = false
    public var rotationCamera: Bool {
        get {
            return _rotationCamera
        }
        set {
            _rotationCamera = newValue
            self.handleDeviceOrientation()
        }
    }
    
    public var captureDevice: AVCaptureDevice? {
        get {
            return cameraDevice.currentDevice
        }
    }
    
    public var isRecording: Bool {
        get {
            return self.cameraOutput.isRecording
        }
    }
    
    public var isAdjustingFocus: Bool {
        get {
            if let `captureDevice` = captureDevice {
                return captureDevice.isAdjustingFocus
            }
            
            return false
        }
    }
    
    public var isAdjustingExposure: Bool {
        get {
            if let `captureDevice` = captureDevice {
                return captureDevice.isAdjustingExposure
            }
            
            return false
        }
    }
    
    public var isAdjustingWhiteBalance: Bool {
        get {
            if let `captureDevice` = captureDevice {
                return captureDevice.isAdjustingWhiteBalance
            }
            
            return false
        }
    }
    
    public static var sharedInstance: CameraEngine = CameraEngine()
    
    public override init() {
        super.init()
        self.setupSession()
    }
    
    deinit {
        self.stopSession()
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupSession() {
        self.sessionQueue.async { () -> Void in
            self.configureInputDevice()
            self.configureOutputDevice()
            self.handleDeviceOrientation()
        }
    }
    
    public class func askAuthorization() -> AVAuthorizationStatus {
        return AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
    }
    
    //MARK: Session management
    
    public func startSession() {
        let session = self.session
        
        self.sessionQueue.async { () -> Void in
            session.startRunning()
        }
    }
    
    public func stopSession() {
        let session = self.session
        
        self.sessionQueue.async { () -> Void in
            session.stopRunning()
        }
    }
    
    //MARK: Device management
    
    private func handleDeviceOrientation() {
        if self.rotationCamera {
			if (!UIDevice.current.isGeneratingDeviceOrientationNotifications) {
				UIDevice.current.beginGeneratingDeviceOrientationNotifications()
			}
            NotificationCenter.default.addObserver(forName: NSNotification.Name.UIDeviceOrientationDidChange, object: nil, queue: OperationQueue.main) { (_) -> Void in
                self.previewLayer.connection?.videoOrientation = AVCaptureVideoOrientation.orientationFromUIDeviceOrientation(UIDevice.current.orientation)
            }
        }
        else {
			if (UIDevice.current.isGeneratingDeviceOrientationNotifications) {
				UIDevice.current.endGeneratingDeviceOrientationNotifications()
			}
            NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIDeviceOrientationDidChange, object: nil)
        }
    }
    
    public func changeCurrentDevice(_ position: AVCaptureDevice.Position) {
        self.cameraDevice.changeCurrentDevice(position)
        self.configureInputDevice()
    }
    
    public func compatibleCameraFocus() -> [CameraEngineCameraFocus] {
        if let currentDevice = self.cameraDevice.currentDevice {
            return CameraEngineCameraFocus.availableFocus().filter {
                return currentDevice.isFocusModeSupported($0.foundationFocus())
            }
        }
        else {
            return []
        }
    }
    
    public func compatibleSessionPresset() -> [CameraEngineSessionPreset] {
        return CameraEngineSessionPreset.availablePresset().filter {
            return self.session.canSetSessionPreset(AVCaptureSession.Preset(rawValue: $0.foundationPreset()))
        }
    }
    
    public func compatibleVideoEncoderPresset() -> [CameraEngineVideoEncoderEncoderSettings] {
        return CameraEngineVideoEncoderEncoderSettings.availableFocus()
    }
    
    public func compatibleDetectionMetadata() -> [CameraEngineCaptureOutputDetection] {
        return CameraEngineCaptureOutputDetection.availableDetection()
    }
    
    private func configureFlash(_ mode: AVCaptureDevice.FlashMode) {
        if let currentDevice = self.cameraDevice.currentDevice, currentDevice.isFlashAvailable && self.capturePhotoSettings.flashMode != mode {
            self.capturePhotoSettings.flashMode = mode
        }
//        if let currentDevice = self.cameraDevice.currentDevice, currentDevice.isFlashAvailable && currentDevice.flashMode != mode {
//            do {
//                try currentDevice.lockForConfiguration()
//                currentDevice.flashMode = mode
//                currentDevice.unlockForConfiguration()
//            }
//            catch {
//                fatalError("[CameraEngine] error lock configuration device")
//            }
//        }
    }
    
    private func configureTorch(_ mode: AVCaptureDevice.TorchMode) {
        if let currentDevice = self.cameraDevice.currentDevice, currentDevice.isTorchAvailable && currentDevice.torchMode != mode {
            do {
                try currentDevice.lockForConfiguration()
                currentDevice.torchMode = mode
                currentDevice.unlockForConfiguration()
            }
            catch {
                fatalError("[CameraEngine] error lock configuration device")
            }
        }
    }
    
    public func switchCurrentDevice() {
        if self.isRecording == false {
            self.changeCurrentDevice((self.cameraDevice.currentPosition == .back) ? .front : .back)
        }
    }
    
    public var currentDevice: AVCaptureDevice.Position {
        get {
            return self.cameraDevice.currentPosition
        }
        set {
            self.changeCurrentDevice(newValue)
        }
    }
    
    //MARK: Device I/O configuration
    
    private func configureInputDevice() {
        do {
            if let currentDevice = self.cameraDevice.currentDevice {
                try self.cameraInput.configureInputCamera(self.session, device: currentDevice)
            }
            if let micDevice = self.cameraDevice.micCameraDevice {
                try self.cameraInput.configureInputMic(self.session, device: micDevice)
            }
        }
        catch CameraEngineDeviceInputErrorType.unableToAddCamera {
            fatalError("[CameraEngine] unable to add camera as InputDevice")
        }
        catch CameraEngineDeviceInputErrorType.unableToAddMic {
            fatalError("[CameraEngine] unable to add mic as InputDevice")
        }
        catch {
            fatalError("[CameraEngine] error initInputDevice")
        }
    }
    
    private func configureOutputDevice() {
        self.cameraOutput.configureCaptureOutput(self.session, sessionQueue: self.sessionQueue)
        self.cameraMetadata.previewLayer = self.previewLayer
        self.cameraMetadata.configureMetadataOutput(self.session, sessionQueue: self.sessionQueue, metadataType: self.metadataDetection)
    }
}

//MARK: Extension Device

public extension CameraEngine {
    
    public func focus(_ atPoint: CGPoint) {
        if let currentDevice = self.cameraDevice.currentDevice {
			let performFocus = currentDevice.isFocusModeSupported(.autoFocus) && currentDevice.isFocusPointOfInterestSupported
			let performExposure = currentDevice.isExposureModeSupported(.autoExpose) && currentDevice.isExposurePointOfInterestSupported
            if performFocus || performExposure {
                let focusPoint = self.previewLayer.captureDevicePointConverted(fromLayerPoint: atPoint)
                do {
                    try currentDevice.lockForConfiguration()
					
					if performFocus {
						currentDevice.focusPointOfInterest = CGPoint(x: focusPoint.x, y: focusPoint.y)
						if currentDevice.focusMode == AVCaptureDevice.FocusMode.locked {
							currentDevice.focusMode = AVCaptureDevice.FocusMode.autoFocus
						} else {
							currentDevice.focusMode = AVCaptureDevice.FocusMode.continuousAutoFocus
						}
					}
					
                    if performExposure {
						currentDevice.exposurePointOfInterest = CGPoint(x: focusPoint.x, y: focusPoint.y)
                        if currentDevice.exposureMode == AVCaptureDevice.ExposureMode.locked {
                            currentDevice.exposureMode = AVCaptureDevice.ExposureMode.autoExpose
                        } else {
                            currentDevice.exposureMode = AVCaptureDevice.ExposureMode.continuousAutoExposure;
                        }
                    }
                    currentDevice.unlockForConfiguration()
                }
                catch {
                    fatalError("[CameraEngine] error lock configuration device")
                }
            }
        }
    }
}

//MARK: Extension capture

public extension CameraEngine {
    
    public func capturePhoto(_ blockCompletion: @escaping blockCompletionCapturePhoto) {
        self.cameraOutput.capturePhoto(settings: self.capturePhotoSettings, blockCompletion)
    }
	
	public func capturePhotoBuffer(_ blockCompletion: @escaping blockCompletionCapturePhotoBuffer) {
        self.cameraOutput.capturePhotoBuffer(settings: self.capturePhotoSettings, blockCompletion)
	}
    
    public func startRecordingVideo(_ url: URL, blockCompletion: @escaping blockCompletionCaptureVideo) {
        if self.isRecording == false {
            self.sessionQueue.async(execute: { () -> Void in
                self.cameraOutput.startRecordVideo(blockCompletion, url: url)
            })
        }
    }
    
    public func stopRecordingVideo() {
        if self.isRecording {
            self.sessionQueue.async(execute: { () -> Void in
                self.cameraOutput.stopRecordVideo()
            })
        }
    }
    
    public func createGif(_ fileUrl: URL, frames: [UIImage], delayTime: Float, loopCount: Int = 0, completionGif: @escaping blockCompletionGifEncoder) {
        self.cameraGifEncoder.blockCompletionGif = completionGif
        self.cameraGifEncoder.createGif(fileUrl, frames: frames, delayTime: delayTime, loopCount: loopCount)
    }
}
