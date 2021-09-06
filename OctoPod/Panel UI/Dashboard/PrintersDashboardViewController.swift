import UIKit

private let reuseIdentifier = "PrinterCell"
private let cameraReuseIdentifier = "cameraGridCell"

class PrintersDashboardViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {

    let printerManager: PrinterManager = { return (UIApplication.shared.delegate as! AppDelegate).printerManager! }()
    var printers: Array<PrinterObserver> = []
    var panelViewController: PanelViewController?
    var cameraEmbeddedViewControllers: Array<CameraEmbeddedViewController> = Array()
    var displayCameras = false

    @IBOutlet weak var collectionView: UICollectionView!
    @IBOutlet weak var toggleDisplayButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Disable estimated size for iOS 10 since it crashes on iPad and iPhone Plus
        let os = ProcessInfo().operatingSystemVersion
        if let layout = self.collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            layout.estimatedItemSize = os.majorVersion == 10 ? CGSize(width: 0, height: 0) : UICollectionViewFlowLayout.automaticSize
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Theme background color
        let currentTheme = Theme.currentTheme()
        collectionView.backgroundColor = currentTheme.backgroundColor()
        self.view.backgroundColor = currentTheme.backgroundColor()
        self.toggleDisplayButton.backgroundColor = currentTheme.backgroundColor()

        printers = []
        for printer in printerManager.getPrinters() {
            // Only add printers that want to be displayed in dashboard
            if printer.includeInDashboard {
                let printerObserver = PrinterObserver(printersDashboardViewController: self, row: printers.count)
                printerObserver.connectToServer(printer: printer)
                printers.append(printerObserver)
            }
        }
        // Create embedded VCs (but will not be rendered yet)
        self.addEmbeddedCameraViewControllers()
        self.updateButtonIcon()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        for printerObserver in printers {
            printerObserver.disconnectFromServer()
        }
        // Remove embedded VCs
        self.deleteEmbeddedCameraViewControllers()
        printers = []
    }
    
    @IBAction func toggleCameraOrPanel(_ sender: Any) {
        displayCameras = !displayCameras
        self.collectionView.reloadData()
        self.updateButtonIcon()
    }
    
    // MARK: UICollectionViewDataSource

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return displayCameras ? cameraEmbeddedViewControllers.count : printers.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if displayCameras {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: cameraReuseIdentifier, for: indexPath) as! CameraGridViewCell
        
            // Add embedded VC as a child view and use the view of the embedded VC as the view of the cell
            let embeddedVC = cameraEmbeddedViewControllers[indexPath.row]
            self.addChild(embeddedVC)
            cell.hostedView = embeddedVC.view
            // Display printer name at the top of the video in the cell
            if let cameraLabel = embeddedVC.cameraLabel {
                embeddedVC.topCameraLabel.text = cameraLabel
                embeddedVC.topCameraLabel.isHidden = false
            } else {
                embeddedVC.topCameraLabel.isHidden = true
            }

            return cell

        } else {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath) as! PrinterViewCell
        
            if let printerObserver = printers[safeIndex: indexPath.row] {
                // Configure the cell
                cell.printerLabel.text = printerObserver.printerName
                cell.printerStatusLabel.text = printerObserver.printerStatus
                cell.progressLabel.text = printerObserver.progress
                cell.printTimeLabel.text = printerObserver.printTime
                cell.printTimeLeftLabel.text = printerObserver.printTimeLeft
                cell.printEstimatedCompletionLabel.text = printerObserver.printCompletion
                cell.layerLabel.text = printerObserver.layer
            }
        
            return cell
        }
    }

    // MARK: UICollectionViewDelegateFlowLayout
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if displayCameras {
            let ratio = cameraEmbeddedViewControllers[indexPath.row].cameraRatio!
            let width: CGFloat
            if UIDevice.current.orientation == .portrait || UIDevice.current.orientation == .portraitUpsideDown {
                // iPhone in vertical position
                width = collectionView.frame.width - 20
            } else {
                // iPhone in horizontal position
                width = collectionView.frame.width / 2 - 15 // Substract for spacing
            }
            return CGSize(width: width, height: width * ratio)
        } else {
            let devicePortrait = UIApplication.shared.statusBarOrientation.isPortrait
            let portraitWidth = devicePortrait ? UIScreen.main.bounds.width : UIScreen.main.bounds.height
            if portraitWidth <= 320 {
                // Set cell width to fit in SE screen
                return CGSize(width: 265, height: 205)
            } else {
                // Set cell width to fit in any screen other than SE screen
                return CGSize(width: 300, height: 205)
            }
        }
    }
    
    // MARK: UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if let printer = printerManager.getPrinterByName(name: printers[indexPath.row].printerName) {
            selectNewDefaultPrinter(printer: printer)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if !displayCameras {
            let theme = Theme.currentTheme()
            let textColor = theme.textColor()
            let labelColor = theme.labelColor()
            
            cell.backgroundColor = theme.cellBackgroundColor()
            if let cell = cell as? PrinterViewCell {
                cell.printerLabel?.textColor = textColor
                cell.printedTextLabel?.textColor = labelColor
                cell.printTimeTextLabel?.textColor = labelColor
                cell.printTimeLeftTextLabel?.textColor = labelColor
                cell.printEstimatedCompletionTextLabel?.textColor = labelColor
                cell.printerStatusTextLabel?.textColor = labelColor
                cell.printerStatusLabel?.textColor = textColor
                
                cell.progressLabel?.textColor = textColor
                cell.printTimeLabel?.textColor = textColor
                cell.printTimeLeftLabel?.textColor = textColor
                cell.printEstimatedCompletionLabel?.textColor = textColor
                cell.layerTextLabel?.textColor = labelColor
                cell.layerLabel?.textColor = textColor
            }
        }
    }
        
    // MARK: Connection notifications
    
    func refreshItem(row: Int) {
        if !displayCameras {
            DispatchQueue.main.async {
                // Check that list of printers is still in sync with what is being displayed
                if self.printers.count > row {
                    self.collectionView.reloadItems(at: [IndexPath(row: row, section: 0)])
                }
            }
        }
    }

    // MARK: Private functions
    
    fileprivate func selectNewDefaultPrinter(printer: Printer) {
        // Notify of newly selected printer
        panelViewController?.changeDefaultPrinter(printer: printer)
        // Close this window and go back
        navigationController?.popViewController(animated: true)
    }
    
    fileprivate func updateButtonIcon() {
        let image = self.displayCameras ? UIImage(named: "Camera") : UIImage(named: "TextPanel")
        self.toggleDisplayButton.setImage(image, for: .normal)
    }
    
    fileprivate func addEmbeddedCameraViewControllers() {
        for printer in printerManager.getPrinters() {
//            if let cameras = printer.getMultiCameras(), cameras.count > 1 {
//                // MultiCam plugin is installed so show all cameras
//                let multiCamera = cameras[1]
//                var cameraOrientation: UIImage.Orientation
//                var cameraURL: String
//                let url = multiCamera.cameraURL
//                let ratio = multiCamera.streamRatio == "16:9" ? CGFloat(0.5625) : CGFloat(0.75)
//
//                if url == printer.getStreamPath() {
//                    // This is camera hosted by OctoPrint so respect orientation
//                    cameraURL = CameraUtils.shared.absoluteURL(hostname: printer.hostname, streamUrl: url)
//                    cameraOrientation = UIImage.Orientation(rawValue: Int(printer.cameraOrientation))!
//                } else {
//                    if url.starts(with: "/") {
//                        // Another camera hosted by OctoPrint so build absolute URL
//                        cameraURL = CameraUtils.shared.absoluteURL(hostname: printer.hostname, streamUrl: url)
//                    } else {
//                        // Use absolute URL to render camera
//                        cameraURL = url
//                    }
//                    // Respect orientation defined by MultiCamera plugin
//                    cameraOrientation = UIImage.Orientation(rawValue: Int(multiCamera.cameraOrientation))!
//                }
//
//                cameraEmbeddedViewControllers.append(newEmbeddedCameraViewController(index: 0, label: printer.name, cameraRatio: ratio, url: cameraURL, cameraOrientation: cameraOrientation))
//            }


            if printer.includeInDashboard && !printer.hideCamera {
                // MultiCam plugin is not installed so just show default camera
                let cameraURL = CameraUtils.shared.absoluteURL(hostname: printer.hostname, streamUrl: printer.getStreamPath())
                let cameraOrientation = UIImage.Orientation(rawValue: Int(printer.cameraOrientation))!
                let ratio = printer.firstCameraAspectRatio16_9 ? CGFloat(0.5625) : CGFloat(0.75)
                let printerURL = printer.objectID.uriRepresentation().absoluteString
                cameraEmbeddedViewControllers.append(newEmbeddedCameraViewController(printerURL: printerURL, index: 0, label: printer.name, cameraRatio: ratio, url: cameraURL, cameraOrientation: cameraOrientation))
            }
        }
    }
    
    fileprivate func deleteEmbeddedCameraViewControllers() {
        for cameraEmbeddedViewController in cameraEmbeddedViewControllers {
            cameraEmbeddedViewController.removeFromParent()
        }
        cameraEmbeddedViewControllers.removeAll()
    }
    
    fileprivate func newEmbeddedCameraViewController(printerURL: String, index: Int, label: String, cameraRatio: CGFloat, url: String, cameraOrientation: UIImage.Orientation) -> CameraEmbeddedViewController {
        var controller: CameraEmbeddedViewController
        let useHLS = CameraUtils.shared.isHLS(url: url)
        // Let's create a new one. Use one for HLS and another one for MJPEG
        controller = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: useHLS ? "CameraHLSEmbeddedViewController" : "CameraMJPEGEmbeddedViewController") as! CameraEmbeddedViewController
        controller.printerURL = printerURL
        controller.cameraLabel = label
        controller.cameraURL = url
        controller.cameraOrientation = cameraOrientation
        controller.infoGesturesAvailable = false
        controller.cameraTappedCallback = {(embeddedVC: CameraEmbeddedViewController) -> Void in
            if let url = embeddedVC.printerURL, let idURL = URL(string: url), let printer = self.printerManager.getPrinterByObjectURL(url: idURL) {
                DispatchQueue.main.async {
                    self.selectNewDefaultPrinter(printer: printer)
                }
            }
        }
        controller.cameraViewDelegate = nil
        controller.cameraIndex = index
        controller.cameraRatio = cameraRatio
        controller.camerasViewController = nil
        controller.muteVideo = true
        return controller
    }
}
