//
//  LaunchView.swift
//  TrollInstallerX
//
//  Created by Alfie on 22/03/2024.
//

import SwiftUI

struct MainView: View {
    
    @State private var isInstalling = false
    @State private var installMode = 0          // 0 = 普通安装，1 = 越狱安装
    @State private var jb = JailbreakDetector.check()
    
    @State private var device: Device = Device()
    
    @State private var isShowingMDCAlert = false
    @State private var isShowingOTAAlert = false
    @State private var isShowingHelperAlert = false
    
    @State private var isShowingSettings = false
    @State private var isShowingCredits = false
    
    @State private var installedSuccessfully = false
    @State private var installationFinished = false
    
    // Best way to show the alert midway through doInstall()
    @ObservedObject var helperView = HelperAlert.shared
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ZStack {
                    LinearGradient(colors: [Color(hex: 0x0482d1), Color(hex: 0x0566ed)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .ignoresSafeArea()
                    VStack {
                        VStack {
                            Image("Icon")
                                .resizable()
                                .cornerRadius(22)
                                .frame(maxWidth: 100, maxHeight: 100)
                                .shadow(radius: 10)
                            Text("TrollInstallerX")
                                .font(.system(size: 30, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                            Text("By Alfie CG")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.5))
                            Text("iOS 14.0 - 16.6.1")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .padding(.vertical)
                        
                        if !isInstalling {
                            MenuView(isShowingSettings: $isShowingSettings, isShowingCredits: $isShowingCredits, isShowingMDCAlert: $isShowingMDCAlert, isShowingOTAAlert: $isShowingOTAAlert, device: device)
                                .frame(maxWidth: geometry.size.width / 1.2, maxHeight: geometry.size.height / 4)
                                .transition(.scale)
                                .padding()
                                .shadow(radius: 10)
                                .disabled(!device.isSupported)
                        }
                        
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .foregroundColor(.white.opacity(0.15))
                                .frame(maxWidth: geometry.size.width / 1.2)
                                .frame(maxHeight: isInstalling ? geometry.size.height / 1.75 : 60)
                                .transition(.scale)
                                .shadow(radius: 10)
                            if isInstalling {
                                LogView(installationFinished: $installationFinished)
                                    .padding()
                                    .frame(maxWidth: geometry.size.width / 1.2)
                                    .frame(maxHeight: geometry.size.height / 1.75)
                            }
                            else {
                                VStack(spacing: 10) {
                                    Button(action: {
                                        if !isShowingCredits && !isShowingSettings && !isShowingMDCAlert && !isShowingOTAAlert {
                                            installMode = 0
                                            UIImpactFeedbackGenerator().impactOccurred()
                                            withAnimation { isInstalling.toggle() }
                                        }
                                    }, label: {
                                        Text(device.isSupported ? "普通安装（不越狱）" : "Unsupported")
                                                .font(.system(size: 19, weight: .semibold, design: .rounded))
                                                .foregroundColor(device.isSupported ? .white : .secondary)
                                                .padding()
                                                .frame(maxWidth: geometry.size.width / 1.2, maxHeight: 56)
                                                .background(RoundedRectangle(cornerRadius: 10).foregroundColor(.white.opacity(0.18)))
                                    })

                                    Button(action: {
                                        if !isShowingCredits && !isShowingSettings && !isShowingMDCAlert && !isShowingOTAAlert && jb.isJailbroken {
                                            installMode = 1
                                            UIImpactFeedbackGenerator().impactOccurred()
                                            withAnimation { isInstalling.toggle() }
                                        }
                                    }, label: {
                                        VStack(spacing: 2) {
                                            Text("越狱安装（TrollStore Helper）")
                                                .font(.system(size: 19, weight: .semibold, design: .rounded))
                                                .foregroundColor(jb.isJailbroken ? .white : .secondary)
                                            Text(jb.isJailbroken ? jb.summary : "未检测到越狱，此入口不可用")
                                                .font(.system(size: 12, design: .rounded))
                                                .foregroundColor(.white.opacity(0.55))
                                        }
                                        .padding()
                                        .frame(maxWidth: geometry.size.width / 1.2, maxHeight: 64)
                                        .background(RoundedRectangle(cornerRadius: 10).foregroundColor(jb.isJailbroken ? .green.opacity(0.28) : .white.opacity(0.08)))
                                    })
                                    .disabled(!jb.isJailbroken)
                                }
                            }
                        }
                        .padding()
                        .disabled(!device.isSupported)
                        
                        
                        }
                        .blur(radius: (isShowingMDCAlert || isShowingOTAAlert || isShowingSettings || isShowingCredits || helperView.showAlert) ? 10 : 0)
                    }
                }
                if isShowingOTAAlert {
                    PopupView(isShowingAlert: $isShowingOTAAlert, content: {
                        TrollHelperOTAView(arm64eVersion: .constant(false))
                    })
                }
                if isShowingMDCAlert {
                    PopupView(isShowingAlert: $isShowingMDCAlert, shouldAllowDismiss: false, content: {
                        UnsandboxView(isShowingMDCAlert: $isShowingMDCAlert)
                    })
                }
                if isShowingSettings {
                    PopupView(isShowingAlert: $isShowingSettings, content: {
                        SettingsView(device: device)
                    })
                }
                
                if isShowingCredits {
                    PopupView(isShowingAlert: $isShowingCredits, content: {
                        CreditsView()
                    })
                }
            
            if helperView.showAlert {
                PopupView(isShowingAlert: $isShowingHelperAlert, shouldAllowDismiss: false, content: {
                    PersistenceHelperView(isShowingHelperAlert: $isShowingHelperAlert, allowNoPersistenceHelper: device.supportsDirectInstall)
                    })
                }
            }
            // Hacky, but it works (can't pass helperView.showAlert as a binding variable)
            .onChange(of: helperView.showAlert) { new in
                if new {
                    withAnimation {
                        isShowingHelperAlert = true
                    }
                }
            }
            .onChange(of: isShowingHelperAlert) { new in
                if !new {
                    helperView.showAlert = false
                }
            }
            .onChange(of: isInstalling) { _ in
                Task {
                    if device.isSupported {
                        if installMode == 1 {
                            installedSuccessfully = await doJailbreakInstall(device)
                        } else if device.supportsDirectInstall {
                            installedSuccessfully = await doDirectInstall(device)
                        } else {
                            installedSuccessfully = await doIndirectInstall(device)
                        }
                        installationFinished = true
                    }
                    UINotificationFeedbackGenerator().notificationOccurred(installedSuccessfully ? .success : .error)
                }
            }
            .onChange(of: isShowingOTAAlert) { new in
                if !new {
                    withAnimation {
                        isShowingMDCAlert = !checkForMDCUnsandbox() && MacDirtyCow.supports(device)
                    }
                }
            }
            .onAppear {
                if device.isSupported {
                    withAnimation {
                        isShowingOTAAlert = device.supportsOTA
                        if !isShowingOTAAlert { isShowingMDCAlert = !checkForMDCUnsandbox() && MacDirtyCow.supports(device) }
                    }
                }
                jb = JailbreakDetector.check()
                Task {
                    await getUpdatedTrollStore()
                }
            }
            .onChange(of: isShowingOTAAlert) { _ in
                if !checkForMDCUnsandbox() && MacDirtyCow.supports(device) && !isShowingOTAAlert && device.supportsOTA { // User has just dismissed alert
                    withAnimation {
                        isShowingMDCAlert = true
                    }
                }
            }
        }
    }


#Preview {
    MainView()
}
