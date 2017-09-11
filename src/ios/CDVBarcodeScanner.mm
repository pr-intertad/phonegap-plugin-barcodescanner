/*
 * PhoneGap is available under *either* the terms of the modified BSD license *or* the
 * MIT License (2008). See http://opensource.org/licenses/alphabetical for full text.
 *
 * Copyright 2011 Matt Kane. All rights reserved.
 * Copyright (c) 2011, IBM Corporation
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>

//------------------------------------------------------------------------------
// use the all-in-one version of zxing that we built
//------------------------------------------------------------------------------
#import "zxing-all-in-one.h"

#import <Cordova/CDVPlugin.h>

//------------------------------------------------------------------------------
// Delegate to handle orientation functions
// 
//------------------------------------------------------------------------------
@protocol CDVBarcodeScannerOrientationDelegate <NSObject>

- (NSUInteger)supportedInterfaceOrientations;
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation;
- (BOOL)shouldAutorotate;

@end

//------------------------------------------------------------------------------
// Adds a shutter button to the UI, and changes the scan from continuous to
// only performing a scan when you click the shutter button.  For testing.
//------------------------------------------------------------------------------
#define USE_SHUTTER 0
#define CONFIG_XIB      @"alternateXib"
#define CONFIG_FORMAT   @"format"
#define CONFIG_WIDTH    @"width"
#define CONFIG_HEIGHT   @"height"

#define DEFAULT_SCALE 0.7

//------------------------------------------------------------------------------
@class CDVbcsProcessor;
@class CDVbcsViewController;


//------------------------------------------------------------------------------
// plugin class
//------------------------------------------------------------------------------
@interface CDVBarcodeScanner : CDVPlugin {}
- (NSString*)isScanNotPossible;
- (void)scan:(CDVInvokedUrlCommand*)command;
- (void)encode:(CDVInvokedUrlCommand*)command;
- (void)returnSuccess:(NSString*)scannedText format:(NSString*)format cancelled:(BOOL)cancelled flipped:(BOOL)flipped callback:(NSString*)callback;
- (void)returnError:(NSString*)message callback:(NSString*)callback;
@end

//------------------------------------------------------------------------------
// class that does the grunt work
//------------------------------------------------------------------------------
@interface CDVbcsProcessor : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate> {}
@property (nonatomic, retain) CDVBarcodeScanner*           plugin;
@property (nonatomic, retain) NSString*                   callback;
@property (nonatomic, retain) UIViewController*           parentViewController;
@property (nonatomic, retain) CDVbcsViewController*        viewController;
@property (nonatomic, retain) AVCaptureSession*           captureSession;
@property (nonatomic, retain) AVCaptureVideoPreviewLayer* previewLayer;
@property (nonatomic, retain) NSString*                   alternateXib;
@property (nonatomic, retain) NSString*                   formats;
@property (nonatomic)         double                      scanHeight;
@property (nonatomic)         double                      scanWidth;
@property (nonatomic)         AVCaptureVideoOrientation   captureOrientation;
@property (nonatomic)         BOOL                        is1D;
@property (nonatomic)         BOOL                        is2D;
@property (nonatomic)         BOOL                        capturing;
@property (nonatomic)         BOOL                        isFrontCamera;
@property (nonatomic)         BOOL                        torchIsPresent;
@property (nonatomic)         BOOL                        isFlashLightOn;
@property (nonatomic)         BOOL                        isFlipped;


- (id)initWithPlugin:(CDVBarcodeScanner*)plugin callback:(NSString*)callback parentViewController:(UIViewController*)parentViewController config:(NSDictionary *)config;
- (void)scanBarcode;
- (void)barcodeScanSucceeded:(NSString*)text format:(NSString*)format;
- (void)barcodeScanFailed:(NSString*)message;
- (void)barcodeScanCancelled;
- (void)openDialog;
- (NSString*)setUpCaptureSession;
- (void)captureOutput:(AVCaptureOutput*)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection*)connection;
- (NSString*)formatStringFrom:(zxing::BarcodeFormat)format;
- (zxing::BarcodeFormat)formatFrom:(NSString*)formatString;
- (UIImage*)getImageFromSample:(CMSampleBufferRef)sampleBuffer;
- (zxing::Ref<zxing::LuminanceSource>) getLuminanceSourceFromSample:(CMSampleBufferRef)sampleBuffer imageBytes:(uint8_t**)ptr;
- (UIImage*) getImageFromLuminanceSource:(zxing::LuminanceSource*)luminanceSource;
- (void)dumpImage:(UIImage*)image;
@end

//------------------------------------------------------------------------------
// view controller for the ui
//------------------------------------------------------------------------------
@interface CDVbcsViewController : UIViewController <CDVBarcodeScannerOrientationDelegate> {}
@property (nonatomic, retain) CDVbcsProcessor*  processor;
@property (nonatomic, retain) NSString*        alternateXib;
@property (nonatomic)         BOOL             shutterPressed;
@property (nonatomic, retain) IBOutlet UIView* overlayView;
// unsafe_unretained is equivalent to assign - used to prevent retain cycles in the property below
@property (nonatomic, unsafe_unretained) id orientationDelegate;

- (id)initWithProcessor:(CDVbcsProcessor*)processor alternateOverlay:(NSString *)alternateXib;
- (void)startCapturing;
- (UIView*)buildOverlayView;
- (UIImage*)buildReticleImage: (CGRect) rectArea;
- (void)shutterButtonPressed;
- (IBAction)cancelButtonPressed:(id)sender;

@end

//------------------------------------------------------------------------------
// plugin class
//------------------------------------------------------------------------------
@implementation CDVBarcodeScanner

//--------------------------------------------------------------------------
- (NSString*)isScanNotPossible {
    NSString* result = nil;
    
    Class aClass = NSClassFromString(@"AVCaptureSession");
    if (aClass == nil) {
        return @"AVFoundation Framework not available";
    }
    
    return result;
}

//--------------------------------------------------------------------------
- (void)scan:(CDVInvokedUrlCommand*)command {
    CDVbcsProcessor* processor;
    NSString*       callback;
    NSString*       capabilityError;
    
    callback = command.callbackId;
    
    // We allow the user to define an alternate xib file for loading the overlay. 
    NSDictionary *config = nil;
    
    if ( [command.arguments count] >= 1 )
    {
        config = [command.arguments objectAtIndex:0];
    }
    
    capabilityError = [self isScanNotPossible];
    if (capabilityError) {
        [self returnError:capabilityError callback:callback];
        return;
    }
    
    processor = [[CDVbcsProcessor alloc]
                 initWithPlugin:self
                 callback:callback
                 parentViewController:self.viewController
                 config:config
                 ];
    [processor retain];
    [processor retain];
    [processor retain];
    // queue [processor scanBarcode] to run on the event loop
    [processor performSelector:@selector(scanBarcode) withObject:nil afterDelay:0];
}

//--------------------------------------------------------------------------
- (void)encode:(CDVInvokedUrlCommand*)command {
    [self returnError:@"encode function not supported" callback:command.callbackId];
}

//--------------------------------------------------------------------------
- (void)returnSuccess:(NSString*)scannedText format:(NSString*)format cancelled:(BOOL)cancelled flipped:(BOOL)flipped callback:(NSString*)callback{
    NSNumber* cancelledNumber = [NSNumber numberWithInt:(cancelled?1:0)];
    
    NSMutableDictionary* resultDict = [[[NSMutableDictionary alloc] init] autorelease];
    [resultDict setObject:scannedText     forKey:@"text"];
    [resultDict setObject:format          forKey:@"format"];
    [resultDict setObject:cancelledNumber forKey:@"cancelled"];
    
    CDVPluginResult* result = [CDVPluginResult
                               resultWithStatus: CDVCommandStatus_OK
                               messageAsDictionary: resultDict
                               ];
    
    NSString* js = [result toSuccessCallbackString:callback];
    if (!flipped) {
        [self writeJavascript:js];
    }
}

//--------------------------------------------------------------------------
- (void)returnError:(NSString*)message callback:(NSString*)callback {
    CDVPluginResult* result = [CDVPluginResult
                               resultWithStatus: CDVCommandStatus_OK
                               messageAsString: message
                               ];
    
    NSString* js = [result toErrorCallbackString:callback];
    
    [self writeJavascript:js];
}

@end

//------------------------------------------------------------------------------
// class that does the grunt work
//------------------------------------------------------------------------------
@implementation CDVbcsProcessor

@synthesize plugin               = _plugin;
@synthesize callback             = _callback;
@synthesize parentViewController = _parentViewController;
@synthesize viewController       = _viewController;
@synthesize captureSession       = _captureSession;
@synthesize previewLayer         = _previewLayer;
@synthesize alternateXib         = _alternateXib;
@synthesize is1D                 = _is1D;
@synthesize is2D                 = _is2D;
@synthesize capturing            = _capturing;

//--------------------------------------------------------------------------
- (id)initWithPlugin:(CDVBarcodeScanner*)plugin
            callback:(NSString*)callback
parentViewController:(UIViewController*)parentViewController
  config:(NSDictionary *)config {
    self = [super init];
    if (!self) return self;
    
    self.plugin               = plugin;
    self.callback             = callback;
    self.parentViewController = parentViewController;
    
    if (config != nil) {
        self.alternateXib         = [config objectForKey:CONFIG_XIB];
        self.formats              = [config objectForKey: CONFIG_FORMAT];
        self.scanHeight           = [[config objectForKey: CONFIG_HEIGHT] doubleValue];
        self.scanWidth            = [[config objectForKey: CONFIG_WIDTH] doubleValue];
    }
    
    if (self.scanHeight <= 0 || self.scanHeight > 1)
    {
        self.scanHeight = -1;
    }
    if (self.scanWidth <= 0 || self.scanWidth > 1)
    {
        self.scanWidth = -1;
    }
    
    self.is1D      = YES;
    self.is2D      = YES;
    self.capturing = NO;
    
    return self;
}

//--------------------------------------------------------------------------
- (void)dealloc {
    self.plugin = nil;
    self.callback = nil;
    self.parentViewController = nil;
    self.viewController = nil;
    self.captureSession = nil;
    self.previewLayer = nil;
    self.alternateXib = nil;
    
    self.capturing = NO;
    
    [super dealloc];
}

//--------------------------------------------------------------------------
- (void)scanBarcode {
    
//    self.captureSession = nil;
//    self.previewLayer = nil;
    NSString* errorMessage = [self setUpCaptureSession];
    if (errorMessage) {
        [self barcodeScanFailed:errorMessage];
        return;
    }
    
    self.viewController = [[[CDVbcsViewController alloc] initWithProcessor: self alternateOverlay:self.alternateXib] autorelease];
    // here we set the orientation delegate to the MainViewController of the app (orientation controlled in the Project Settings)
    self.viewController.orientationDelegate = self.plugin.viewController;
    
    // delayed [self openDialog];
    [self performSelector:@selector(openDialog) withObject:nil afterDelay:1];
}

//--------------------------------------------------------------------------
- (void)openDialog {
    [self.parentViewController
     presentModalViewController:self.viewController
     animated:YES
     ];
}

//--------------------------------------------------------------------------
- (void)barcodeScanDone {
    self.capturing = NO;
    [self.captureSession stopRunning];
    [self.parentViewController dismissModalViewControllerAnimated: YES];
    
    // viewcontroller holding onto a reference to us, release them so they
    // will release us
    self.viewController = nil;
    
    // delayed [self release];
    [self performSelector:@selector(release) withObject:nil afterDelay:1];
}

//--------------------------------------------------------------------------
- (void)barcodeScanSucceeded:(NSString*)text format:(NSString*)format {
    [self barcodeScanDone];
    [self.plugin returnSuccess:text format:format cancelled:FALSE flipped:FALSE callback:self.callback];
}

//--------------------------------------------------------------------------
- (void)barcodeScanFailed:(NSString*)message {
    [self barcodeScanDone];
    [self.plugin returnError:message callback:self.callback];
}

//--------------------------------------------------------------------------
- (void)barcodeScanCancelled {
    [self barcodeScanDone];
    [self.plugin returnSuccess:@"" format:@"" cancelled:TRUE flipped:self.isFlipped callback:self.callback];
    if (self.isFlipped) {
        self.isFlipped = NO;
    }
}


- (void)flipCamera
{
    self.isFlipped = YES;
    self.isFrontCamera = !self.isFrontCamera;
    [self performSelector:@selector(barcodeScanCancelled) withObject:nil afterDelay:0];
    [self performSelector:@selector(scanBarcode) withObject:nil afterDelay:0.1];
}

- (void)toggleFlashlight
{
    if (self.isFrontCamera) {
        return;
    }
    
    AVCaptureDevice* __block device = nil;
    if (!self.isFrontCamera) {
        device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if (!device || !device.hasFlash) return;
    }
    
    [device lockForConfiguration:nil];
    
    // Set torch on/off
    if (self.isFlashLightOn) {
        [device setTorchModeOnWithLevel:0.5 error:nil];
    } else {
        [device setTorchMode:AVCaptureTorchModeOff];
    }
    
    // Commit configuration
    [device unlockForConfiguration];
}

//--------------------------------------------------------------------------
- (NSString*)setUpCaptureSession {
    NSError* error = nil;
    
    AVCaptureSession* captureSession = [[[AVCaptureSession alloc] init] autorelease];
    self.captureSession = captureSession;
    self.torchIsPresent = NO;
    
       AVCaptureDevice* __block device = nil;
    if (self.isFrontCamera) {
        NSArray* devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
        [devices enumerateObjectsUsingBlock:^(AVCaptureDevice *obj, NSUInteger idx, BOOL *stop) {
            if (obj.position == AVCaptureDevicePositionFront) {
                device = obj;
            }
        }];
    } else {
        device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if (!device) return @"unable to obtain video capture device";
    }
    
    self.torchIsPresent = (device && device.hasFlash);
    
    NSLog(@"setUpCaptureSession");
    
    AVCaptureDeviceInput* input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (!input) return @"unable to obtain video capture device input";
    
    AVCaptureVideoDataOutput* output = [[[AVCaptureVideoDataOutput alloc] init] autorelease];
    if (!output) return @"unable to obtain video capture output";
    
    NSDictionary* videoOutputSettings = [NSDictionary
                                         dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA]
                                         forKey:(id)kCVPixelBufferPixelFormatTypeKey
                                         ];
    
    output.alwaysDiscardsLateVideoFrames = YES;
    output.videoSettings = videoOutputSettings;
    
    [output setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
    
    if (![captureSession canSetSessionPreset:AVCaptureSessionPresetMedium]) {
        return @"unable to preset medium quality video capture";
    }
    
    captureSession.sessionPreset = AVCaptureSessionPresetMedium;
    
    if ([captureSession canAddInput:input]) {
        [captureSession addInput:input];
    }
    else {
        return @"unable to add video capture device input to session";
    }
    
    if ([captureSession canAddOutput:output]) {
        [captureSession addOutput:output];
    }
    else {
        return @"unable to add video capture output to session";
    }
    
    // setup capture preview layer
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:captureSession];
    
    // run on next event loop pass [captureSession startRunning]
    [captureSession performSelector:@selector(startRunning) withObject:nil afterDelay:0];
    
    return nil;
}

//--------------------------------------------------------------------------
// this method gets sent the captured frames
//--------------------------------------------------------------------------
- (void)captureOutput:(AVCaptureOutput*)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection*)connection {
    
    if (!self.capturing) return;
    
    if ([connection isVideoOrientationSupported]) {
        [connection setVideoOrientation: self.captureOrientation];
    }
    
#if USE_SHUTTER
    if (!self.viewController.shutterPressed) return;
    self.viewController.shutterPressed = NO;
    
    UIView* flashView = [[[UIView alloc] initWithFrame:self.viewController.view.frame] autorelease];
    [flashView setBackgroundColor:[UIColor whiteColor]];
    [self.viewController.view.window addSubview:flashView];
    
    [UIView
     animateWithDuration:.4f
     animations:^{
         [flashView setAlpha:0.f];
     }
     completion:^(BOOL finished){
         [flashView removeFromSuperview];
     }
     ];
    
    //         [self dumpImage: [[self getImageFromSample:sampleBuffer] autorelease]];
#endif
    
    
    using namespace zxing;
    
    // LuminanceSource is pretty dumb; we have to give it a pointer to
    // a byte array, but then can't get it back out again.  We need to
    // get it back to free it.  Saving it in imageBytes.
    uint8_t* imageBytes;
    
    //        NSTimeInterval timeStart = [NSDate timeIntervalSinceReferenceDate];
    
    try {
        DecodeHints decodeHints;
        
        if (self.formats != nil)
        {
            NSArray *items = [self.formats componentsSeparatedByString:@","];
            
            for (id item in items)
            {
                NSString* formatString = (NSString*)item;
                
                decodeHints.addFormat([self formatFrom:formatString]);
            }
        }
        else
        {
            decodeHints.addFormat(BarcodeFormat_QR_CODE);
            decodeHints.addFormat(BarcodeFormat_DATA_MATRIX);
            decodeHints.addFormat(BarcodeFormat_UPC_E);
            decodeHints.addFormat(BarcodeFormat_UPC_A);
            decodeHints.addFormat(BarcodeFormat_EAN_8);
            decodeHints.addFormat(BarcodeFormat_EAN_13);
            decodeHints.addFormat(BarcodeFormat_CODE_128);
            decodeHints.addFormat(BarcodeFormat_CODE_39);
            decodeHints.addFormat(BarcodeFormat_ITF);
        }
        
        // here's the meat of the decode process
        Ref<LuminanceSource>   luminanceSource   ([self getLuminanceSourceFromSample: sampleBuffer imageBytes:&imageBytes]);
        // [self dumpImage: [[self getImageFromLuminanceSource:luminanceSource] autorelease]];
        Ref<Binarizer>         binarizer         (new HybridBinarizer(luminanceSource));
        Ref<BinaryBitmap>      bitmap            (new BinaryBitmap(binarizer));
        Ref<MultiFormatReader> reader            (new MultiFormatReader());
        Ref<Result>            result            (reader->decode(bitmap, decodeHints));
        Ref<String>            resultText        (result->getText());
        BarcodeFormat          formatVal =       result->getBarcodeFormat();
        NSString*              format    =       [self formatStringFrom:formatVal];
        
        
        const char* cString      = resultText->getText().c_str();
        NSString*   resultString = [[[NSString alloc] initWithCString:cString encoding:NSUTF8StringEncoding] autorelease];
        
        [self barcodeScanSucceeded:resultString format:format];
        
    }
    catch (zxing::ReaderException &rex) {
        //            NSString *message = [[[NSString alloc] initWithCString:rex.what() encoding:NSUTF8StringEncoding] autorelease];
        //            NSLog(@"decoding: ReaderException: %@", message);
    }
    catch (zxing::IllegalArgumentException &iex) {
        //            NSString *message = [[[NSString alloc] initWithCString:iex.what() encoding:NSUTF8StringEncoding] autorelease];
        //            NSLog(@"decoding: IllegalArgumentException: %@", message);
    }
    catch (...) {
        //            NSLog(@"decoding: unknown exception");
        //            [self barcodeScanFailed:@"unknown exception decoding barcode"];
    }
    
    //        NSTimeInterval timeElapsed  = [NSDate timeIntervalSinceReferenceDate] - timeStart;
    //        NSLog(@"decoding completed in %dms", (int) (timeElapsed * 1000));
    
    // free the buffer behind the LuminanceSource
    if (imageBytes) {
        free(imageBytes);
    }
}

//--------------------------------------------------------------------------
// convert barcode format to string
//--------------------------------------------------------------------------
- (NSString*)formatStringFrom:(zxing::BarcodeFormat)format {
    if (format == zxing::BarcodeFormat_QR_CODE)      return @"QR_CODE";
    if (format == zxing::BarcodeFormat_DATA_MATRIX)  return @"DATA_MATRIX";
    if (format == zxing::BarcodeFormat_UPC_E)        return @"UPC_E";
    if (format == zxing::BarcodeFormat_UPC_A)        return @"UPC_A";
    if (format == zxing::BarcodeFormat_EAN_8)        return @"EAN_8";
    if (format == zxing::BarcodeFormat_EAN_13)       return @"EAN_13";
    if (format == zxing::BarcodeFormat_CODE_128)     return @"CODE_128";
    if (format == zxing::BarcodeFormat_CODE_39)      return @"CODE_39";
    if (format == zxing::BarcodeFormat_VIN_CODE)     return @"VIN_CODE";
    if (format == zxing::BarcodeFormat_ITF)          return @"ITF";
    return @"???";
}

//--------------------------------------------------------------------------
// convert string to barcode format
//--------------------------------------------------------------------------
- (zxing::BarcodeFormat)formatFrom:(NSString*)formatString {
    if ([formatString isEqualToString: @"QR_CODE"])		return zxing::BarcodeFormat_QR_CODE;
    if ([formatString isEqualToString: @"DATA_MATRIX"])	return zxing::BarcodeFormat_DATA_MATRIX;
    if ([formatString isEqualToString: @"UPC_E"])		return zxing::BarcodeFormat_UPC_E;
    if ([formatString isEqualToString: @"UPC_A"])		return zxing::BarcodeFormat_UPC_A;
    if ([formatString isEqualToString: @"EAN_8"])		return zxing::BarcodeFormat_EAN_8;
    if ([formatString isEqualToString: @"EAN_13"])		return zxing::BarcodeFormat_EAN_13;
    if ([formatString isEqualToString: @"CODE_128"])	return zxing::BarcodeFormat_CODE_128;
    if ([formatString isEqualToString: @"CODE_39"])		return zxing::BarcodeFormat_CODE_39;
    if ([formatString isEqualToString: @"VIN_CODE"])    return zxing::BarcodeFormat_VIN_CODE;
    if ([formatString isEqualToString: @"ITF"])		    return zxing::BarcodeFormat_ITF;
    return zxing::BarcodeFormat_None;
}
//--------------------------------------------------------------------------
// convert capture's sample buffer (scanned picture) into the thing that
// zxing needs.
//--------------------------------------------------------------------------
- (zxing::Ref<zxing::LuminanceSource>) getLuminanceSourceFromSample:(CMSampleBufferRef)sampleBuffer imageBytes:(uint8_t**)ptr {
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    size_t   bytesPerRow =            CVPixelBufferGetBytesPerRow(imageBuffer);
    size_t   width       =            CVPixelBufferGetWidth(imageBuffer);
    size_t   height      =            CVPixelBufferGetHeight(imageBuffer);
    uint8_t* baseAddress = (uint8_t*) CVPixelBufferGetBaseAddress(imageBuffer);
    
    size_t minAxis = MIN(width, height);
    
    // only going to get 40% of the height of the captured image
    size_t    greyWidth  = (self.scanWidth == -1) ? minAxis*DEFAULT_SCALE : self.scanWidth * width;
    size_t    greyHeight  = (self.scanHeight == -1) ? minAxis*DEFAULT_SCALE: self.scanHeight * height;
    
    uint8_t*  greyData   = (uint8_t*) malloc(greyWidth * greyHeight);
    
    // remember this pointer so we can free it later
    *ptr = greyData;
    
    if (!greyData) {
        CVPixelBufferUnlockBaseAddress(imageBuffer,0);
        throw new zxing::ReaderException("out of memory");
    }
    
    size_t offsetX = (width - greyWidth) / 2;
    size_t offsetY = (height - greyHeight) / 2;
    
    // pixel-by-pixel ...
    for (size_t i=0; i<greyHeight; i++) {
        for (size_t j=0; j<greyWidth; j++) {
            // i,j are the coordinates from the sample buffer
            // ni, nj are the coordinates in the LuminanceSource
            // in this case, there's a rotation taking place
            size_t ni = i;
            size_t nj = j;
            
            size_t baseOffset = (i+offsetY)*bytesPerRow + (j + offsetX)*4;
            
            // convert from color to grayscale
            // http://en.wikipedia.org/wiki/Grayscale#Converting_color_to_grayscale
            size_t value = 0.11 * baseAddress[baseOffset] +
            0.59 * baseAddress[baseOffset + 1] +
            0.30 * baseAddress[baseOffset + 2];

            greyData[ni*greyWidth+nj] = value;
        }
    }
    
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    
    using namespace zxing;
    
    Ref<LuminanceSource> luminanceSource (
                                          new GreyscaleLuminanceSource(greyData, greyWidth, greyHeight, 0, 0, greyWidth, greyHeight)
                                          );
    
    return luminanceSource;
}

//--------------------------------------------------------------------------
// for debugging
//--------------------------------------------------------------------------
- (UIImage*) getImageFromLuminanceSource:(zxing::LuminanceSource*)luminanceSource  {
    unsigned char* bytes = luminanceSource->getMatrix();
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
    CGContextRef context = CGBitmapContextCreate(
                                                 bytes,
                                                 luminanceSource->getWidth(), luminanceSource->getHeight(), 8, luminanceSource->getWidth(),
                                                 colorSpace,
                                                 kCGImageAlphaNone
                                                 );
    
    CGImageRef cgImage = CGBitmapContextCreateImage(context);
    UIImage*   image   = [[UIImage alloc] initWithCGImage:cgImage];
    
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    CGImageRelease(cgImage);
    free(bytes);
    
    return image;
}

//--------------------------------------------------------------------------
// for debugging
//--------------------------------------------------------------------------
- (UIImage*)getImageFromSample:(CMSampleBufferRef)sampleBuffer {
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    size_t width       = CVPixelBufferGetWidth(imageBuffer);
    size_t height      = CVPixelBufferGetHeight(imageBuffer);
    
    uint8_t* baseAddress    = (uint8_t*) CVPixelBufferGetBaseAddress(imageBuffer);
    int      length         = height * bytesPerRow;
    uint8_t* newBaseAddress = (uint8_t*) malloc(length);
    memcpy(newBaseAddress, baseAddress, length);
    baseAddress = newBaseAddress;
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
                                                 baseAddress,
                                                 width, height, 8, bytesPerRow,
                                                 colorSpace,
                                                 kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst
                                                 );
    
    CGImageRef cgImage = CGBitmapContextCreateImage(context);
    UIImage*   image   = [[UIImage alloc] initWithCGImage:cgImage];
    
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    CGImageRelease(cgImage);
    
    free(baseAddress);
    
    return image;
}

//--------------------------------------------------------------------------
// for debugging
//--------------------------------------------------------------------------
- (void)dumpImage:(UIImage*)image {
    NSLog(@"writing image to library: %dx%d", (int)image.size.width, (int)image.size.height);
    ALAssetsLibrary* assetsLibrary = [[[ALAssetsLibrary alloc] init] autorelease];
    [assetsLibrary
     writeImageToSavedPhotosAlbum:image.CGImage
     orientation:ALAssetOrientationUp
     completionBlock:^(NSURL* assetURL, NSError* error){
         if (error) NSLog(@"   error writing image to library");
         else       NSLog(@"   wrote image to library %@", assetURL);
     }
     ];
}

@end

//------------------------------------------------------------------------------
// view controller for the ui
//------------------------------------------------------------------------------
@implementation CDVbcsViewController
@synthesize processor      = _processor;
@synthesize shutterPressed = _shutterPressed;
@synthesize alternateXib   = _alternateXib;
@synthesize overlayView    = _overlayView;

//--------------------------------------------------------------------------
- (id)initWithProcessor:(CDVbcsProcessor*)processor alternateOverlay:(NSString *)alternateXib {
    self = [super init];
    if (!self) return self;
    
    self.processor = processor;
    self.shutterPressed = NO;
    self.alternateXib = alternateXib;
    self.overlayView = nil;
    return self;
}

//--------------------------------------------------------------------------
- (void)dealloc {
    self.view = nil;
//    self.processor = nil;
    self.shutterPressed = NO;
    self.alternateXib = nil;
    self.overlayView = nil;      
    [super dealloc];
}

//--------------------------------------------------------------------------
- (void)loadView {
    self.view = [[[UIView alloc] initWithFrame: self.processor.parentViewController.view.frame] autorelease];
    
    // setup capture preview layer
    AVCaptureVideoPreviewLayer* previewLayer = self.processor.previewLayer;
    previewLayer.frame = self.view.bounds;
    previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    
    [self.view.layer insertSublayer:previewLayer below:[[self.view.layer sublayers] objectAtIndex:0]];
    
    [self.view addSubview:[self buildOverlayView]];
}

//--------------------------------------------------------------------------
- (void)viewWillAppear:(BOOL)animated {

    //Get Preview Layer connection
    AVCaptureConnection *previewLayerConnection=self.processor.previewLayer.connection;
    
    // set video orientation to what the camera sees
    UIInterfaceOrientation appOrientation = [[UIApplication sharedApplication] statusBarOrientation];
    
    if (appOrientation == UIInterfaceOrientationLandscapeLeft) {
        self.processor.captureOrientation = AVCaptureVideoOrientationLandscapeLeft;
    } else if (appOrientation == UIInterfaceOrientationLandscapeRight) {
        self.processor.captureOrientation = AVCaptureVideoOrientationLandscapeRight;
    } else {
        self.processor.captureOrientation = AVCaptureVideoOrientationPortrait;
    }
    
    if ([previewLayerConnection isVideoOrientationSupported]) {
        [previewLayerConnection setVideoOrientation: self.processor.captureOrientation];
    }
    
    // this fixes the bug when the statusbar is landscape, and the preview layer
    // starts up in portrait (not filling the whole view)
    
    // self.processor.previewLayer.frame = self.view.bounds;

    self.processor.previewLayer.frame = [[UIScreen mainScreen] bounds];
}

//--------------------------------------------------------------------------
- (void)viewDidAppear:(BOOL)animated {
    
    [self startCapturing];
    
    [super viewDidAppear:animated];
}

//--------------------------------------------------------------------------
- (void)startCapturing {
    self.processor.capturing = YES;
}

//--------------------------------------------------------------------------
- (void)shutterButtonPressed {
    self.shutterPressed = YES;
}

//--------------------------------------------------------------------------
- (IBAction)cancelButtonPressed:(id)sender {
    [self.processor performSelector:@selector(barcodeScanCancelled) withObject:nil afterDelay:0];
}

- (void)flipCameraButtonPressed:(id)sender
{
    [self.processor performSelector:@selector(flipCamera) withObject:nil afterDelay:0];
}

- (void)flashLightButtonPressed:(UIButton*)flashLightButton
{
    [flashLightButton setSelected: ![flashLightButton isSelected]];
    [self.processor setIsFlashLightOn: [flashLightButton isSelected]];
    [self.processor performSelector:@selector(toggleFlashlight) withObject:nil afterDelay:0];
}

//--------------------------------------------------------------------------
- (UIView *)buildOverlayViewFromXib 
{
    [[NSBundle mainBundle] loadNibNamed:self.alternateXib owner:self options:NULL];
    
    if ( self.overlayView == nil )
    {
        NSLog(@"%@", @"An error occurred loading the overlay xib.  It appears that the overlayView outlet is not set.");
        return nil;
    }
    
    return self.overlayView;        
}

//--------------------------------------------------------------------------
- (UIView*)buildOverlayView {
    
    if ( nil != self.alternateXib )
    {
        return [self buildOverlayViewFromXib];
    }
    CGRect bounds = self.view.bounds;
    bounds = CGRectMake(0, 0, bounds.size.width, bounds.size.height);
    
    UIView* overlayView = [[[UIView alloc] initWithFrame:bounds] autorelease];
    overlayView.autoresizesSubviews = YES;
    overlayView.autoresizingMask    = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlayView.opaque              = NO;
    
    UIToolbar* toolbar = [[[UIToolbar alloc] init] autorelease];
    toolbar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    
    id cancelButton = [[[UIBarButtonItem alloc] autorelease]
                       initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                       target:(id)self
                       action:@selector(cancelButtonPressed:)
                       ];
    
    
    id flexSpace = [[[UIBarButtonItem alloc] autorelease]
                    initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                    target:nil
                    action:nil
                    ];
    
    id flipCamera = [[[UIBarButtonItem alloc] autorelease]
                       initWithBarButtonSystemItem:UIBarButtonSystemItemCamera
                       target:(id)self
                       action:@selector(flipCameraButtonPressed:)
                       ];
    
#if USE_SHUTTER
    id shutterButton = [[UIBarButtonItem alloc]
                        initWithBarButtonSystemItem:UIBarButtonSystemItemCamera
                        target:(id)self
                        action:@selector(shutterButtonPressed)
                        ];
    
    toolbar.items = [NSArray arrayWithObjects:flexSpace,cancelButton,flexSpace, flipCamera ,shutterButton,nil];
#else
    toolbar.items = [NSArray arrayWithObjects:flexSpace,cancelButton,flexSpace, flipCamera,nil];
#endif
    bounds = overlayView.bounds;
    
    [toolbar sizeToFit];
    CGFloat toolbarHeight  = [toolbar frame].size.height;
    CGFloat rootViewHeight = CGRectGetHeight(bounds);
    CGFloat rootViewWidth  = CGRectGetWidth(bounds);
    CGRect  rectArea       = CGRectMake(0, rootViewHeight - toolbarHeight, rootViewWidth, toolbarHeight);
    [toolbar setFrame:rectArea];
    
    [overlayView addSubview: toolbar];
    
    rectArea = CGRectMake(
                          0,
                          0,
                          rootViewHeight,
                          rootViewWidth
                          );
    
    UIImage* reticleImage = [self buildReticleImage: rectArea];
    UIView* reticleView = [[[UIImageView alloc] initWithImage: reticleImage] autorelease];

    
    [reticleView setFrame:overlayView.bounds];
    
    reticleView.opaque           = NO;
    reticleView.contentMode      = UIViewContentModeScaleToFill;
    reticleView.autoresizingMask = (UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth);

    
    if (self.processor.torchIsPresent) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        
        NSBundle* bundle = [NSBundle bundleWithURL:[[NSBundle mainBundle]URLForResource:@"CDVBarcodeScanner" withExtension:@"bundle"]];
        
        NSString *normalPath = [bundle pathForResource:@"Normal" ofType:@"png"];
        NSString *selectedPath = [bundle pathForResource:@"Selected" ofType:@"png"];
        
        [button addTarget:self action:@selector(flashLightButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
        [button setBackgroundImage:[UIImage imageWithContentsOfFile:normalPath] forState:UIControlStateNormal];
        [button setBackgroundImage:[UIImage imageWithContentsOfFile:selectedPath] forState:UIControlStateSelected];
        
        button.frame = CGRectMake(10, 10, 40, 40);
        
        [overlayView addSubview:button];
    }
    
    [overlayView addSubview: reticleView];
    
    return overlayView;
}

//--------------------------------------------------------------------------

#define RETICLE_SIZE    500.0f
#define RETICLE_WIDTH     3.0f
#define RETICLE_OFFSET_X  0.0f
#define RETICLE_OFFSET_Y  0.0f
#define RETICLE_ALPHA     0.4f
#define RETICLE_PADDING  10.0f

//-------------------------------------------------------------------------
// builds the green box and red line
//-------------------------------------------------------------------------
- (UIImage*)buildReticleImage: (CGRect) rectArea
{
    UIImage* result;
    UIGraphicsBeginImageContext(rectArea.size);
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    size_t minAxis = MIN(rectArea.size.height, rectArea.size.width);
    
    size_t height = (self.processor.scanHeight == -1) ?
                        minAxis*DEFAULT_SCALE
                        : rectArea.size.height*self.processor.scanHeight;
    
    size_t width = (self.processor.scanWidth == -1) ?
                        minAxis*DEFAULT_SCALE
                        : rectArea.size.width*self.processor.scanWidth;
    
    size_t x0 = (rectArea.size.width-width)/2;
    size_t y0 = (rectArea.size.height-height)/2;
    
    size_t x1 = x0 + width;
    
    if (self.processor.is1D) {
        size_t y = y0 + height/2;
        
        UIColor* color = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:RETICLE_ALPHA];
        CGContextSetStrokeColorWithColor(context, color.CGColor);
        CGContextSetLineWidth(context, RETICLE_WIDTH);
        CGContextBeginPath(context);
        CGContextMoveToPoint(context, x0+0.5*RETICLE_WIDTH, y);
        CGContextAddLineToPoint(context, x1, y);
        CGContextStrokePath(context);
    }
    
    if (self.processor.is2D) {
        UIColor* color = [UIColor colorWithRed:0.0 green:1.0 blue:0.0 alpha:RETICLE_ALPHA];
        CGContextSetStrokeColorWithColor(context, color.CGColor);
        CGContextSetLineWidth(context, RETICLE_WIDTH);
        CGContextStrokeRect(context,
                            CGRectMake(
                                       x0,
                                       y0,
                                       width,
                                       height
                                       )
                            );
    }
    
    result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

#pragma mark CDVBarcodeScannerOrientationDelegate

- (BOOL)shouldAutorotate
{   
    return YES;
}

//- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation
// {
//     return UIInterfaceOrientationLandscapeRight;
// }

- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskLandscape;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector:@selector(shouldAutorotateToInterfaceOrientation:)]) {
        return [self.orientationDelegate shouldAutorotateToInterfaceOrientation:interfaceOrientation];
    }
    
    return YES;
}

- (void) willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)orientation duration:(NSTimeInterval)duration
{
    [CATransaction begin];
    
    //Get Preview Layer connection
    AVCaptureConnection *previewLayerConnection=self.processor.previewLayer.connection;
    
    if ([previewLayerConnection isVideoOrientationSupported]) {
        [previewLayerConnection setVideoOrientation: orientation];
    }
    
    self.processor.captureOrientation = orientation;
    
    [self.processor.previewLayer layoutSublayers];
    self.processor.previewLayer.frame = self.view.bounds;
    
    [CATransaction commit];
    [super willAnimateRotationToInterfaceOrientation:orientation duration:duration];
}

@end
