//
//  ViewController.swift
//  demo-ios
//
//  Created by Stan on 8/27/15.
//  Copyright (c) 2015 Ably. All rights reserved.
//

import UIKit
import GradientView
import IHKeyboardAvoiding

class EditNameViewController: UIViewController {

    @IBOutlet weak var nameTextField: UITextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        IHKeyboardAvoiding.setAvoidingView(self.view)

        let rootView = self.view as! GradientView
        rootView.colors = [UIColor.whiteColor(), UIColor(white: 0.87, alpha: 1)]
        rootView.locations = [0.2, 0.95]
        rootView.mode = .Radial
    }

    override func shouldPerformSegueWithIdentifier(identifier: String?, sender: AnyObject?) -> Bool {
        return nameTextField.text != nil && !nameTextField.text!.isEmpty
    }
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        self.nameTextField.endEditing(true)
        
        let clientId = nameTextField.text
        let chatViewController = segue.destinationViewController as! ChatViewController;
        chatViewController.clientId = clientId
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction func primaryActionTriggered(sender: AnyObject) {
        self.performSegueWithIdentifier("DefaultSegue", sender: self)
    }
}

