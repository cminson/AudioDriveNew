//
//  RecordingView.swift
//
//  Copyright © 2020 Christopher Minson. All rights reserved.
//

import SwiftUI
import Foundation
import SystemConfiguration
import AVFoundation
import CoreMedia
import lame
import Speech


let NATIVE_AUDIO_SUFFIX = ".m4a"
let MP3_AUDIO_SUFFIX = ".mp3"
let TRANSCRIPT_SUFFIX = ".txt"
let AUDIO_PREFIX = "ad."
let APP_TITLE = "Audio Drive"
let GOOGLE_DRIVE_ROOT_FOLDER = "!ROOT!"     // special string indicating upload is root directory, not subfolder
let MAX_DECIBLES : Float = 70.0

var AveragePower : Float? = 0.0
var AudioFileName : String = ""
var AudioFilePath : String = ""
var AudioTranscriptName : String = ""
var AudioTranscriptPath : String = ""

var AudioEngine : AVAudioEngine!
var AudioFile : AVAudioFile!
var AudioPlayer : AVAudioPlayerNode!
var Outref: ExtAudioFileRef?
var AudioFilePlayer: AVAudioPlayerNode!
var Mixer : AVAudioMixerNode!
var IsPlay = false
var MP3Active = false

var TMP_WAV_PATH = ""
let TMP_WAV_NAME = "tmp.wav"

var ActiveSet = Set<String>()

var TimerClock : Timer!
var RecordingTime : Int = 0
var RecordingActive: Bool! = false

var DOCUMENTS_URL : URL!
var DOCUMENTS_PATH = ""




enum RecordingState {                   // states of the recording player
    case INITIAL
    case RECORDING
    case FINISHED
}


struct RecordingView: View {
    
    @State private var selection: String?  = ""
    @State private var elapsedTime: Int = 0
    @State private var recordingState: RecordingState = .INITIAL
    
    init() {
                
        AudioEngine = AVAudioEngine()
        AudioFilePlayer = AVAudioPlayerNode()
        Mixer = AVAudioMixerNode()
        AudioEngine.attach(AudioFilePlayer)
        AudioEngine.attach(Mixer)
        
        Settings().loadSettings()
        
        DOCUMENTS_URL = FileManager().urls(for: .documentDirectory, in: .userDomainMask).first!
        DOCUMENTS_PATH = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] + "/"
        TMP_WAV_PATH = DOCUMENTS_PATH + TMP_WAV_NAME
        
        deactivateRecordingUI()

        
        //requestTranscribePermissions()
    }

    var body: some View {
        
        NavigationView {
        
            VStack(alignment: .center, spacing: 0) {
                //Spacer()
                Text(self.elapsedTime.displayInClockFormat())
                /*
                    .onReceive(timer) { input in
                        self.elapsedTime = input
                                }
                 */
                    .font(.system(size: 20, weight: .bold))
                Spacer().frame(height: 20)

                Button(action: {
                    // todo
                })
                {
                    //Image(systemName: self.stateTalkPlayer == .PLAYING ? "pause.fill" : "play.fill")
                    Image(systemName: "play.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 100)
                        .foregroundColor(Color(UIColor.label))
                }

                
                Spacer().frame(height: 20)
                Text(displayRecordingState())
                    .font(.system(size: 20, weight: .bold))
                //Spacer()

            }
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Spacer()

                    Button(action: {

                    })
                    {
                        Text("Settings")
                    }
                    Spacer()
                }
                    
            }
           // end toolbar

        }
        .navigationViewStyle(StackNavigationViewStyle())
        .navigationBarTitle("Audio Drive", displayMode: .inline)

        //.frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        //.edgesIgnoringSafeArea(.all)
        //.background(Color.black)
        //.background(NavigationLink(destination: HelpPageView(), tag: "HELP", selection: $selection) { EmptyView() } .hidden())
    }
    
    
    func updateRecordingTimeDisplay() {
        
        RecordingTime += 1
        
        //let displayCS = (RecordingTime % 100)
        let displaySecond = (RecordingTime / 100) % 60
        let displayMinute = (RecordingTime / (100 * 60)) % 60
        let displayHour = RecordingTime / (100 * 60 * 60)
        
        //UIRecordingTimer.text = String(format: "%02d:%02d:%02d:%02d", displayHour, displayMinute, displaySecond, displayCS)
        //UIRecordingTimer.text = String(format: "%02d:%02d:%02d", displayHour, displayMinute, displaySecond)

    }

    
    func displayRecordingState() -> String {
        
        var displayState: String
        
        switch recordingState {
        case .INITIAL:
            displayState = "Start Recording"
        case .RECORDING:
            displayState = "Recording"
        case .FINISHED:
            displayState = "Start Recording"
        }
       
        return displayState
    }
    
    
    // record the MP3.  Painfully use lame to tap into the byte stream and perform the encoding
    func startRecording() {


        var sampleRateLAME : Int32 = 44100
        let numberChannels : UInt32 =  1
        
        let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
        print("TIMER", type(of: timer))

        // configure to create WAV recording, start it
        try! AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playAndRecord)
        try! AVAudioSession.sharedInstance().setActive(true)

        let sampleRate = AVAudioSession.sharedInstance().sampleRate
        sampleRateLAME = Int32(sampleRate)
        
        let format = AVAudioFormat(commonFormat: AVAudioCommonFormat.pcmFormatInt16,
                                    sampleRate: sampleRate,
             channels: numberChannels,
             interleaved: true)
                 
        print("connect  \(sampleRate) \(sampleRateLAME)")

        AudioEngine.connect(AudioEngine.inputNode, to: Mixer, format: format)
        AudioEngine.connect(Mixer, to: AudioEngine.mainMixerNode, format: format)

        _ = ExtAudioFileCreateWithURL(URL(fileURLWithPath: TMP_WAV_PATH) as CFURL,
             kAudioFileWAVEType,
             (format?.streamDescription)!,
             nil,
             AudioFileFlags.eraseFile.rawValue,
             &Outref)


        Mixer.installTap(onBus: 0, bufferSize: AVAudioFrameCount((format?.sampleRate)!), format: format, block: { (buffer: AVAudioPCMBuffer!, time: AVAudioTime!) -> Void in

            let audioBuffer : AVAudioBuffer = buffer
            _ = ExtAudioFileWrite(Outref!, buffer.frameLength, audioBuffer.audioBufferList)
        })

        //try! startTranscription()
        AudioEngine.prepare()
        do {
            try AudioEngine.start()
        } catch (let error) {
            print("Error \(error)")
        }

        
        // begin MP3 mixin
        var rate: Int32 = 96
        switch ConfigAudioBitRate {
        case "96,000":
            rate = 96
        case "128,000":
            rate = 128
        case "192,000":
            rate = 192
        default:
            print("ERROR \(ConfigAudioBitRate)")
            fatalError(ConfigAudioBitRate)
        }
        let numberLAMEChannels : Int32 = 1
        
        //print("rate = \(rate) ")
        MP3Active = true
        var total = 0
        var read = 0
        var write: Int32 = 0

        var pcm: UnsafeMutablePointer<FILE> = fopen(TMP_WAV_PATH, "rb")
        fseek(pcm, 4*1024, SEEK_CUR)
        let mp3: UnsafeMutablePointer<FILE> = fopen(AudioFilePath, "wb")
        let PCM_SIZE: Int = 8192
        let MP3_SIZE: Int32 = 8192
        let pcmbuffer = UnsafeMutablePointer<Int16>.allocate(capacity: Int(PCM_SIZE*2))
        let mp3buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(MP3_SIZE))

        let lame = lame_init()
        lame_set_num_channels(lame, numberLAMEChannels)
        lame_set_mode(lame, MONO)
        
        lame_set_in_samplerate(lame, sampleRateLAME)
        lame_set_brate(lame, rate)
        lame_set_VBR(lame, vbr_off)
        lame_init_params(lame)

        DispatchQueue.global(qos: .default).async {
            while true {
                pcm = fopen(TMP_WAV_PATH, "rb")
                     fseek(pcm, 4*1024 + total, SEEK_CUR)
                     read = fread(pcmbuffer, MemoryLayout<Int16>.size, PCM_SIZE, pcm)
                     if read != 0 {
                         write = lame_encode_buffer(lame, pcmbuffer, nil, Int32(read), mp3buffer, MP3_SIZE)
                         fwrite(mp3buffer, Int(write), 1, mp3)
                         total += read * MemoryLayout<Int16>.size
                         fclose(pcm)
                     } else if !MP3Active {
                         _ = lame_encode_flush(lame, mp3buffer, MP3_SIZE)
                         _ = fwrite(mp3buffer, Int(write), 1, mp3)
                         break
                     } else {
                         fclose(pcm)
                         usleep(50)
                     }
            }
            lame_close(lame)
            fclose(mp3)
            fclose(pcm)
        }
    }
    
    
    // terminate recording.  disconnect the lame tap, stop everywhere, delete the tmp files
    func stopRecording() {

        //stopTranscription()

        // stop audio engine and player
        // then halt the MP3 encoding (by setting MP3Active = false
        AudioFilePlayer.stop()
        AudioEngine.stop()
        Mixer.removeTap(onBus: 0)

        MP3Active = false
        ExtAudioFileDispose(Outref!)

        try! AVAudioSession.sharedInstance().setActive(false)
        deleteFile(named: TMP_WAV_NAME)
        
     }

    
    // cancel recording.  same as stopRecording, except we delete the MP3
    func cancelRecording() {
        
        RecordingActive = false
        stopRecording()

        //UIRecordingButton.setImage(UIImage(named: "nrecorderoff"), for: UIControl.State.normal)
        TimerClock.invalidate()
         
        deactivateRecordingUI()
        
        deleteFile(named: AudioFileName)
        
        //UICancelRecordingButton.isHidden = true
       // UIUploadStatusText.text = "recording cancelled and deleted"
    }
    
    
    func activateRecordingUI() {
        

    }
    
    
    func deactivateRecordingUI() {
        
     }


    func copyFile(srcPath: String, destPath: String) {
    
        let fileManager = FileManager.default
        do {
            try fileManager.copyItem(atPath: srcPath, toPath: destPath)
        } catch (let error) {
            print("Copy Error \(error)")
            return
        }
    }
    
    
    func deleteMP3AudioFiles() {
    
        let fileManager = FileManager.default
        do {
            let audioFileList = try fileManager.contentsOfDirectory(atPath: DOCUMENTS_PATH)
            for audioFileMP3 in audioFileList {
                if audioFileMP3.contains(MP3_AUDIO_SUFFIX) == false {continue}

                deleteFile(named: audioFileMP3)
            }
        } catch (let error) {
            print("deleteMP3AudioFiles Error \(error)")
            return
        }
    }
    
    func audioFileExists(named audioFileName: String) -> Bool {
        
        let filePath = DOCUMENTS_PATH + audioFileName
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: filePath) {
               return true
        } else {
               return false
        }
    }
    
    func deleteNativeAudioFiles() {
       
           let fileManager = FileManager.default
           do {
               let audioFileList = try fileManager.contentsOfDirectory(atPath: DOCUMENTS_PATH)
               for audioFileNative in audioFileList {
                if audioFileNative.contains(NATIVE_AUDIO_SUFFIX) == false {continue}

                //print(audioFileNative)
                deleteFile(named: audioFileNative)
               }
           } catch (let error) {
               print("deleteNativeAudioFiles Error \(error)")
               return
           }
       }
    
    
    func deleteFile(named audioFileName:String) {
   
       do {
            let audioFilePath = "file://" + DOCUMENTS_PATH + audioFileName
            //print(audioFilePath)
            try FileManager.default.removeItem(at: URL(string: audioFilePath)!)
          
       } catch (let error) {
           print("List Error \(error)")
           return
       }
   }
    
    
    func countUploadableFiles() -> Int {
        
        let fileManager = FileManager.default
        do {
            let audioFileList = try fileManager.contentsOfDirectory(atPath: DOCUMENTS_PATH)
            var count = 0
            for audioFile in audioFileList {
                if audioFile.contains(MP3_AUDIO_SUFFIX) == false {continue}
                
                count += 1

            }
            return count
        } catch (let error) {
            print("List Error \(error)")
             return 0
        }
    }
    
    func deleteAllFiles() {
     
         let fileManager = FileManager.default
         do {
             let audioFileList = try fileManager.contentsOfDirectory(atPath: DOCUMENTS_PATH)
             for audioFile in audioFileList {
                deleteFile(named: audioFile)
             }
         } catch (let error) {
             print("deleteAllFiles \(error)")
             return
         }
     }


    func listAllFiles() {
    
        let fileManager = FileManager.default
        do {
            let audioFileList = try fileManager.contentsOfDirectory(atPath: DOCUMENTS_PATH)
            for audioFile in audioFileList {
                print(audioFile)
            }
        } catch (let error) {
            print("List Error \(error)")
            return
        }
    }
    
    
}

struct RecordingView_Previews: PreviewProvider {
    static var previews: some View {
        RecordingView()
    }
}


extension Int {
    
    func displayInCommaFormat() -> String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        return numberFormatter.string(from: NSNumber(value:self))!
    }

    
    func displayInClockFormat() -> String {
        
        let hours = self / 3600
        let modHours = self % 3600
        let minutes = modHours / 60
        let seconds = modHours % 60
                
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = NumberFormatter.Style.decimal
        var hoursStr = numberFormatter.string(from: NSNumber(value:hours)) ?? "00"
        
        //hack so that it looks nice
        if hoursStr.count == 1 { hoursStr = "0" + hoursStr}
        
        let minutesStr = String(format: "%02d", minutes)
        let secondsStr = String(format: "%02d", seconds)
        
        return hoursStr + ":" + minutesStr + ":" + secondsStr
    }
}

extension String {
    var isAlphanumeric: Bool {
        return !isEmpty && range(of: "[^a-zA-Z0-9]", options: .regularExpression) == nil
    }
}

