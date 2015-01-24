class AppDelegate
  extend IB
  outlet :window, NSWindow
  outlet :webView, WebView

  def awakeFromNib
    NSApp.delegate = self
    webView.UIDelegate = self
    webView.setMaintainsBackForwardList(false)
    version = NSBundle.mainBundle.objectForInfoDictionaryKey("CFBundleShortVersionString")
    webView.customUserAgent = "kotori #{version}"

    loadURL("https://esa.io/")
    self.performSelectorInBackground('startPolling', withObject: nil)
  end

  def applicationShouldHandleReopen(application, hasVisibleWindows:flag)
    window.makeKeyAndOrderFront(nil)
    true
  end

  def applicationShouldTerminate(application)
    alert = NSAlert.new.tap do |v|
      v.messageText = "Quit kotori?"
      v.addButtonWithTitle("OK")
      v.addButtonWithTitle("Cancel")
      v.alertStyle = NSWarningAlertStyle
    end

    alert.runModal == NSAlertFirstButtonReturn ? true : false
  end

  def webView(sender, createWebViewWithRequest:request)
    sender.mainFrame.loadRequest(request)
    sender
  end

  # actions
  def showNewPost(sender)
    team = teamName()
    return unless team
    loadURL("https://#{team}.esa.io/posts/new")
  end

  def showHome(sender)
    team = teamName()
    return unless team
    loadURL("https://#{team}.esa.io/")
  end

  def showPosts(sender)
    team = teamName()
    return unless team
    loadURL("https://#{team}.esa.io/posts")
  end

  def showTeam(sender)
    team = teamName()
    return unless team
    loadURL("https://#{team}.esa.io/team")
  end

  def showHelp(sender)
    NSWorkspace.sharedWorkspace.openURL("https://docs.esa.io/".to_nsurl)
  end

  private

  def loadURL(url)
    request = NSURLRequest.requestWithURL(url.to_nsurl)
    webView.mainFrame.loadRequest(request)
  end

  def teamName
    url = webView.mainFrameURL
    if url =~ /https:\/\/(.+)\.esa\.io/
      return $1
    end
    nil
  end

  def startPolling
    puts 'startPolling'
    # http://stackoverflow.com/questions/13202185/why-does-my-http-request-bubble-wrap-fail-to-execute-in-a-grand-central-dispat
    loop do
      puts "last updated_at #{App::Persistence['notification_last_updated_at']}"
      runLoop = NSRunLoop.currentRunLoop
      BW::HTTP.get("http://crx.lvh.me:3000/api/notifications.json") do |response|
        next unless response.ok?
        result_data = BW::JSON.parse(response.body.to_s)
        notifications = result_data['data']['notifications']
        return if result_data['data']['unread_count'] == 0
        # see: https://github.com/fukayatsu/esa-notifier-crx/blob/master/src/js/background.js#L37

        unless App::Persistence['notification_last_updated_at']
          App::Persistence['notification_last_updated_at'] = Time.iso8601(result_data['data']['notifications'][0]['updated_at'])
        end

        result_data['data']['notifications'].reverse.each do |notification|
          updated_at = Time.iso8601(notification['updated_at'])
          if updated_at > App::Persistence['notification_last_updated_at']
            puts 'notify...'
            notify(notification)
            puts 'update last_updated_at'
            App::Persistence['notification_last_updated_at'] = updated_at + 1 # +1 for fractional second
          end
        end

      end
      runLoop.run
      sleep 10
    end
  end

  def notify(notification)
    puts "notify ****"
    p notification
    notification = NSUserNotification.alloc.init.tap do |n|
      n.title = notification['kind']
      n.informativeText = notification['activity']['user']['screen_name']
      n.soundName = NSUserNotificationDefaultSoundName
      n.userInfo = notification['activity']['user']
    end
    NSUserNotificationCenter.defaultUserNotificationCenter.tap do |center|
      center.delegate = self
      center.deliverNotification notification
    end
  end
end
