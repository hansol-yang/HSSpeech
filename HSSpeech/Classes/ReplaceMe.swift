import Speech

@objc public protocol EasyToSpeechDelegate: class {
	@objc optional func speechToTextDidComplete(text: String)
	func recognizerDidStop(continuous: Bool)
}

@available(iOS 10.0, *)
public class EasyToSpeech {
	private let audioEngine: AVAudioEngine = AVAudioEngine()
	private var speechRecognizer: SFSpeechRecognizer?
	private var bufferRequest: SFSpeechAudioBufferRecognitionRequest?
	private var recognitionTask: SFSpeechRecognitionTask?
	private var isFinal: Bool = false
	private var detectionText: String?
	private var detectionTimer: Timer?
	private var locale: String? {
		didSet {
			self.finishMessage = FinishMessage.message(localeString: locale ?? "en-US")
			print(self.finishMessage)
		}
	}
	public var isGranted: Bool = false
	public var delegate: EasyToSpeechDelegate?
	private var finishMessage: String!
	
	public init() {
		self.bufferRequest = SFSpeechAudioBufferRecognitionRequest()
	}
	
	public func requestAuthorization() {
		SFSpeechRecognizer.requestAuthorization { (status) in
			switch status {
			case .authorized:
				print("EasyToSpeech: Authorized.")
				self.isGranted = true
				let audioSession = AVAudioSession.sharedInstance()
				do {
					try audioSession.setCategory(AVAudioSessionCategoryPlayAndRecord, with: .defaultToSpeaker)
				} catch {
					fatalError(error.localizedDescription)
				}
				
			case .denied:
				print("EasyToSpeech: Denied.")
				self.isGranted = false
			case .notDetermined:
				print("EasyToSpeech: Not determined.")
				self.isGranted = false
			case .restricted:
				print("EasyToSpeech: Restricted.")
				self.isGranted = false
			}
		}
	}
	
	public func startToRecognize(locale: String?, continuous: Bool) {
		print("EasyToSpeech: Started to recognize...")
		if bufferRequest == nil {
			bufferRequest = SFSpeechAudioBufferRecognitionRequest()
		}
		
		isFinal = false
		
		let node = audioEngine.inputNode
		let recordingFormat = node.outputFormat(forBus: AVAudioNodeBus(0))
		node.installTap(onBus: AVAudioNodeBus(0), bufferSize: 1024, format: recordingFormat) { (buffer, _) in
			self.bufferRequest?.append(buffer)
		}
		
		audioEngine.prepare()
		do {
			try audioEngine.start()
		} catch {
			fatalError(error.localizedDescription)
		}
		
		speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: locale ?? "en-US"))
		bufferRequest?.shouldReportPartialResults = true
		recognitionTask = speechRecognizer!.recognitionTask(with: bufferRequest!, resultHandler: { (result, error) in
			if let err = error {
				assertionFailure(err.localizedDescription)
				return
			}
			
			if let res = result {
				self.detectionText = res.bestTranscription.formattedString
				self.detectionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false, block: { (_) in
					if self.detectionText == res.bestTranscription.formattedString {
						if !self.isFinal {
							self.isFinal = true
							print("EasyToSpeech: User speech is over.")
							print("EasyToSpeech: \(self.detectionText!)")
							self.delegate?.speechToTextDidComplete?(text: self.detectionText!)
							self.stopToRecognize(continuous: self.detectionText! != self.finishMessage)
						}
					}
				})
			}
		})
	}
	
	public func stopToRecognize(continuous: Bool) {
		print("EasyToSpeech: Stopping to recognize...")
		audioEngine.stop()
		audioEngine.inputNode.removeTap(onBus: AVAudioNodeBus(0))
		audioEngine.inputNode.reset()
		bufferRequest?.endAudio()
		detectionText = nil
		bufferRequest = nil
		recognitionTask = nil
		let _ = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { (timer) in
			if !(self.detectionTimer?.isValid)! {
				timer.invalidate()
				print("EasyToSpeech: Activated")
				self.recognitionTask?.cancel()
				self.delegate?.recognizerDidStop(continuous: continuous)
			}
		}
	}
	
	public func speakWithUtterance(language: String, msg: String, continuous: Bool) {
		let synthesizer = AVSpeechSynthesizer()
		let utterance = AVSpeechUtterance(string: msg)
		let voice = AVSpeechSynthesisVoice(language: language)
		self.locale = language
		utterance.voice = voice
		synthesizer.speak(utterance)
		
		let _ = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { (timer) in
			if !synthesizer.isSpeaking && !(self.detectionTimer?.isValid)! {
				timer.invalidate()
				print("EasyToSpeech: Speech synthesizer is stopped")
				if continuous {
					self.startToRecognize(locale: self.locale, continuous: continuous)
				}
			}
		}
	}
}

enum FinishMessage: String {
	case en = "Finish"
	case ko = "그만"
	
	static func message(localeString: String) -> String {
		switch localeString {
		case "ko-KR":
			return FinishMessage.ko.rawValue
			
		case "en-US":
			return FinishMessage.en.rawValue
			
		default:
			return FinishMessage.en.rawValue
		}
	}
}

