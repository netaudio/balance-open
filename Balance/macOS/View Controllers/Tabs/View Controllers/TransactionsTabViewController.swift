import Cocoa
import SnapKit
import MapKit
import JMSRangeSlider

class TransactionsTabViewController: NSViewController, TransactionsTabViewModelDelegate, SectionedTableViewDelegate, SectionedTableViewDataSource, NSTextFieldDelegate, TextFieldDelegate, PaintCodeDropdownDelegate {
    
    struct InternalNotifications {
        static let CellOpened   = Notification.Name("TransactionsCellOpened")
        static let CellClosed   = Notification.Name("TransactionsCellClosed")
        
        struct Keys {
            static let Cell     = "Cell"
        }
    }
    
    //
    // MARK: - Properties -
    //
    
    var viewModel = TransactionsTabViewModel()
    var previousSelectedIndex = TableIndex.none
    var hoverPreloadWorkItem: DispatchWorkItem?
    
    // MARK: Header
    let searchField = TokenSearchField()
    var isShowingSearchFilters = false
    var isAnimatingSearchFilters = false
    let accountsDropdown = PaintCodeDropdown()
    let categoriesDropdown = PaintCodeDropdown()
    let timeDropdown = PaintCodeDropdown()
    let amountDropdown = PaintCodeDropdown()

    // MARK: Body
    let scrollView = ScrollView()
    let tableView = SectionedTableView()
    let addAccountView = AddNewAccountView()
    
    // Hack for SnapKit bug, must use NSLayoutConstraint instead of the SnapKit Constraint object
    var scrollViewTopConstraint: NSLayoutConstraint!
    
    // MARK: Footer
    let footerView = VisualEffectView()
    let totalField = LabelField()
    let transactionCountField = LabelField()
    
    // MARK: TouchBar
    var touchBarRangeSlider: JMSRangeSlider?
    var touchBarOverLabel: LabelField?
    var touchBarUnderLabel: LabelField?
    
    //
    // MARK: - Lifecycle -
    //
    
    init() {
        super.init(nibName: nil, bundle: nil)
        viewModel.delegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("unsupported")
    }
    
    deinit {
        unregisterForNotifications()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        registerForNotifications()
        reloadData()
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        
        addSearchShortcutMonitor()
        
        async {
            AppDelegate.sharedInstance.resizeWindowToMaxHeight(animated: true)
        }
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear()
        
        removeSearchShortcutMonitor()
    }
    
    //
    // MARK: - View Creation -
    //
    
    override func loadView() {
        self.view = View()
        //createHeader()
        createTable()
        createFooter()
        showAddAccountIfNeeded()
    }
    
    func createHeader() {
        // Hack to separate tokens on El Cap and Sierra
        searchField.textField.kerningOffset = 3.0
        searchField.delegate = self
        searchField.customDelegate = self
        self.view.addSubview(searchField)
        searchField.snp.makeConstraints { make in
            make.top.equalTo(self.view).offset(10)
            make.height.equalTo(29)
            make.left.equalTo(self.view).inset(12)
            make.right.equalTo(self.view).inset(12)
        }
        
        categoriesDropdown.delegate = self
        categoriesDropdown.drawingBackgroundColor = searchTokenBackgroundColors[.category]
        categoriesDropdown.isHidden = true
        categoriesDropdown.items = viewModel.categories
        self.view.addSubview(categoriesDropdown)
        categoriesDropdown.snp.makeConstraints { make in
            make.top.equalTo(searchField.snp.bottom).offset(44)
            make.left.equalTo(self.view).inset(9)
            make.width.equalTo(191)
        }
        
        accountsDropdown.delegate = self
        accountsDropdown.drawingBackgroundColor = searchTokenBackgroundColors[.account]
        accountsDropdown.isHidden = true
        accountsDropdown.items = viewModel.accounts
        self.view.addSubview(accountsDropdown)
        accountsDropdown.snp.makeConstraints { make in
            make.top.equalTo(searchField.snp.bottom).offset(8)
            make.left.equalTo(self.view).inset(9)
            make.width.equalTo(191)
        }
        
        amountDropdown.delegate = self
        amountDropdown.drawingBackgroundColor = searchTokenBackgroundColors[.over]
        amountDropdown.isHidden = true
        amountDropdown.items = viewModel.amounts
        self.view.addSubview(amountDropdown)
        amountDropdown.snp.makeConstraints { make in
            make.top.equalTo(searchField.snp.bottom).offset(44)
            make.right.equalTo(self.view).inset(9)
            make.width.equalTo(191)
        }
        
        timeDropdown.delegate = self
        timeDropdown.drawingBackgroundColor = searchTokenBackgroundColors[.when]
        timeDropdown.isHidden = true
        timeDropdown.items = viewModel.times
        self.view.addSubview(timeDropdown)
        timeDropdown.snp.makeConstraints { make in
            make.top.equalTo(searchField.snp.bottom).offset(8)
            make.right.equalTo(self.view).inset(9)
            make.width.equalTo(191)
        }
    }
    
    fileprivate let noResultsDateFormatter = DateFormatter()
    func createTable() {
        
        scrollView.documentView = tableView
        self.view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.right.equalToSuperview()
            make.bottom.equalToSuperview()
            make.top.equalToSuperview()
        }
        //scrollViewTopConstraint = NSLayoutConstraint(item: scrollView, attribute: .top, relatedBy: .equal, toItem: searchField, attribute: .bottom, multiplier: 1.0, constant: 12)
        //self.view.addConstraint(scrollViewTopConstraint)
        
        tableView.customDelegate = self
        tableView.customDataSource = self
        // TODO: intercellSpacing doesn't seem to allow values lower than 1, so it's rendering as 2 pixels on retina
        tableView.intercellSpacing = CurrentTheme.defaults.cell.intercellSpacing
        tableView.gridColor = CurrentTheme.defaults.cell.spacerColor
        tableView.gridStyleMask = NSTableView.GridLineStyle.solidHorizontalGridLineMask
        tableView.rowHeight = 5000 // Hide grid lines on empty cells
        tableView.selectionHighlightStyle = .none
        
        tableView.reloadData()
     
        view.addSubview(addAccountView)
        addAccountView.snp.makeConstraints{ make in
            make.size.equalToSuperview()
        }
    }
    
    func createFooter() {
        footerView.blendingMode = .withinWindow
        footerView.material = CurrentTheme.defaults.material
        footerView.state = .active
        footerView.layerBackgroundColor = CurrentTheme.defaults.totalFooter.totalBackgroundColor
        self.view.addSubview(footerView)
        footerView.snp.makeConstraints { make in
            make.height.equalTo(0)
            make.left.equalTo(self.view)
            make.right.equalTo(self.view)
            make.bottom.equalTo(self.view)
        }
        
        transactionCountField.alignment = .left
        transactionCountField.font = CurrentTheme.transactions.cell.nameFont
        transactionCountField.textColor = CurrentTheme.defaults.foregroundColor
        transactionCountField.usesSingleLineMode = true
        footerView.addSubview(transactionCountField)
        transactionCountField.snp.makeConstraints { make in
            make.left.equalTo(footerView).offset(10)
            make.centerY.equalTo(footerView).offset(-1)
        }
        
        totalField.font = CurrentTheme.transactions.cell.nameFont
        totalField.alignment = .right
        totalField.setAccessibilityLabel("Transactions Total")
        totalField.usesSingleLineMode = true
        footerView.addSubview(totalField)
        totalField.snp.makeConstraints { make in
            make.right.equalTo(footerView).inset(12)
            make.centerY.equalTo(footerView).offset(-1)
        }
    }
    
    //
    // MARK: - Notifications -
    //
    
    func registerForNotifications() {
        NotificationCenter.addObserverOnMainThread(self, selector: #selector(institutionAdded(_:)), name: Notifications.InstitutionAdded)
        NotificationCenter.addObserverOnMainThread(self, selector: #selector(institutionRemoved(_:)), name: Notifications.InstitutionRemoved)
        
        NotificationCenter.addObserverOnMainThread(self, selector: #selector(accountHidden(_:)), name: Notifications.AccountHidden)
        NotificationCenter.addObserverOnMainThread(self, selector: #selector(accountUnhidden(_:)), name: Notifications.AccountUnhidden)
        
        NotificationCenter.addObserverOnMainThread(self, selector: #selector(syncCompleted(_:)), name: Notifications.SyncCompleted)
        
        NotificationCenter.addObserverOnMainThread(self, selector: #selector(popoverWillShow(_:)), name: Notifications.PopoverWillShow)
        
        NotificationCenter.addObserverOnMainThread(self, selector: #selector(masterCurrencyChanged(_:)), name: Notifications.MasterCurrencyChanged)
    }
    
    func unregisterForNotifications() {
        NotificationCenter.removeObserverOnMainThread(self, name: Notifications.InstitutionAdded)
        NotificationCenter.removeObserverOnMainThread(self, name: Notifications.InstitutionRemoved)
        
        NotificationCenter.removeObserverOnMainThread(self, name: Notifications.AccountHidden)
        NotificationCenter.removeObserverOnMainThread(self, name: Notifications.AccountUnhidden)
        
        NotificationCenter.removeObserverOnMainThread(self, name: Notifications.SyncCompleted)
        
        NotificationCenter.removeObserverOnMainThread(self, name: Notifications.PopoverWillShow)
        
        NotificationCenter.removeObserverOnMainThread(self, name: Notifications.MasterCurrencyChanged)
    }
    
    @objc fileprivate func institutionAdded(_ notification: Notification) {
        if reloadDataIfInForeground() {
            invalidateTouchBar()
            accountsDropdown.items = viewModel.accounts
        }
    }
    
    @objc fileprivate func institutionRemoved(_ notification: Notification) {
        if reloadDataIfInForeground() {
            invalidateTouchBar()
            accountsDropdown.items = viewModel.accounts
        }
    }
    
    @objc fileprivate func accountHidden(_ notification: Notification) {
        reloadDataIfInForeground()
    }
    
    @objc fileprivate func accountUnhidden(_ notification: Notification) {
        reloadDataIfInForeground()
    }
    
    @objc fileprivate func syncCompleted(_ notification: Notification) {
        reloadDataIfInForeground()
    }
    
    @objc fileprivate func popoverWillShow(_ notification: Notification) {
        if viewModel.dataChangedInBackground {
            viewModel.dataChangedInBackground = false
            async(after: 0.5) {
                self.reloadData()
                self.invalidateTouchBar()
                self.accountsDropdown.items = self.viewModel.accounts
            }
        }
    }
    
    @objc fileprivate func masterCurrencyChanged(_ notification: Notification) {
        reloadDataIfInForeground()
    }
    
    @discardableResult fileprivate func reloadDataIfInForeground() -> Bool {
        if AppDelegate.sharedInstance.statusItem.isStatusItemWindowVisible {
            reloadData()
            return true
        } else {
            viewModel.dataChangedInBackground = true
            return false
        }
    }
    
    func reloadData() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(reloadDataDelayed), object: nil)
        self.perform(#selector(reloadDataDelayed), with: nil, afterDelay: 0.5)
    }
    
    @objc private func reloadDataDelayed() {
        viewModel.reloadData()
        showAddAccountIfNeeded()
    }
    
    func reloadDataFinished() {
        tableView.reloadData()
        updateNumberOfTransactionsAndTotal()
        
        // On a fresh install, update categories if needed
        if categoriesDropdown.items.count == 1 {
            categoriesDropdown.items = viewModel.categories
            invalidateTouchBar()
        }
    }
    
    func showAddAccountIfNeeded() {
        addAccountView.hideView(viewModel.accounts.count > 1)
    }
    
    //
    // MARK: - Search -
    //
    
    func textFieldDidBecomeFirstResponder(_ textField: NSTextField) {
        // Analytics
        analytics.trackEvent(withName: "Transactions tab search started")
        showSearchFilters()
    }
    
    override func controlTextDidBeginEditing(_ obj: Notification) {
        showSearchFilters()
    }
    
    func showSearchFilters() {
        guard !isShowingSearchFilters && !isAnimatingSearchFilters else {
            return
        }
        
        tableView.isHoveringEnabled = false
        isAnimatingSearchFilters = true
        
        accountsDropdown.isHidden = false
        categoriesDropdown.isHidden = false
        timeDropdown.isHidden = false
        amountDropdown.isHidden = false
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0, 0, 0.2, 1)
            scrollViewTopConstraint.animator().constant = 12 + 76
            scrollView.animator().needsUpdateConstraints = true
        }, completionHandler: {
            self.isShowingSearchFilters = true
            self.isAnimatingSearchFilters = false
            
            var reorderedSubviews = self.view.subviews.filter({!($0 is PaintCodeDropdown)})
            reorderedSubviews.append(contentsOf: [self.categoriesDropdown, self.accountsDropdown, self.amountDropdown, self.timeDropdown])
            self.view.subviews = reorderedSubviews
        })
    }
    
    func hideSearchFilters(animated: Bool = true) {
        guard isShowingSearchFilters && !isAnimatingSearchFilters else {
            return
        }
        
        isAnimatingSearchFilters = true
        
        var reorderedSubviews = self.view.subviews.filter({!($0 is PaintCodeDropdown)})
        if let index = reorderedSubviews.index(of: scrollView) {
            for dropdown in [self.categoriesDropdown, self.accountsDropdown, self.amountDropdown, self.timeDropdown].reversed() {
                reorderedSubviews.insert(dropdown, at: index)
            }
            self.view.subviews = reorderedSubviews
        }
        
        let completionBlock = {
            self.isShowingSearchFilters = false
            self.isAnimatingSearchFilters = false
            self.tableView.isHoveringEnabled = true
            
            self.accountsDropdown.isHidden = true
            self.categoriesDropdown.isHidden = true
            self.timeDropdown.isHidden = true
            self.amountDropdown.isHidden = true
            
            self.accountsDropdown.close()
            self.categoriesDropdown.close()
            self.timeDropdown.close()
            self.amountDropdown.close()
        }
        
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0, 0, 0.2, 1)
                scrollViewTopConstraint.animator().constant = 12
                scrollView.animator().needsUpdateConstraints = true
            }, completionHandler: completionBlock)
        } else {
            scrollViewTopConstraint.constant = 12
            scrollView.needsUpdateConstraints = true
            scrollView.layer?.transform = CATransform3DIdentity
            completionBlock()
        }
    }
    
    // Refactor so we share core with the touch bar
    func dropdownSelectedIndexChanged(_ dropdown: PaintCodeDropdown) {
        if dropdown == accountsDropdown {
            viewModel.searchTokens[.in] = nil
            viewModel.searchTokens[.account] = nil
            viewModel.searchTokens[.accountMatches] = dropdown.selectedIndex == 0 ? nil : dropdown.items[dropdown.selectedIndex]
            let searchString = Search.createSearchString(forTokens: viewModel.searchTokens)
            performSearch(searchString)
            self.view.window?.makeFirstResponder(self)
        } else if dropdown == categoriesDropdown {
            viewModel.searchTokens[.category] = nil
            viewModel.searchTokens[.categoryMatches] = dropdown.selectedIndex == 0 ? nil : dropdown.items[dropdown.selectedIndex]
            let searchString = Search.createSearchString(forTokens: viewModel.searchTokens)
            performSearch(searchString)
            self.view.window?.makeFirstResponder(self)
        } else if dropdown == timeDropdown {
            viewModel.searchTokens[.before] = nil
            viewModel.searchTokens[.after] = nil
            viewModel.searchTokens[.when] = dropdown.selectedIndex == 0 ? nil : dropdown.items[dropdown.selectedIndex]
            let searchString = Search.createSearchString(forTokens: viewModel.searchTokens)
            performSearch(searchString)
            self.view.window?.makeFirstResponder(self)
        } else if dropdown == amountDropdown {
            // TODO: Definitely don't hard code this this way
            switch dropdown.selectedIndex {
            case 0:
                viewModel.searchTokens[.over] = nil
                viewModel.searchTokens[.under] = nil
            case 1:
                viewModel.searchTokens[.over] = nil
                viewModel.searchTokens[.under] = "$10"
            case 2:
                viewModel.searchTokens[.over] = nil
                viewModel.searchTokens[.under] = "$100"
            case 3:
                viewModel.searchTokens[.over] = "$500"
                viewModel.searchTokens[.under] = nil
            case 4:
                viewModel.searchTokens[.over] = "$100"
                viewModel.searchTokens[.under] = "$500"
            default:
                break
            }
            
            let searchString = Search.createSearchString(forTokens: viewModel.searchTokens)
            performSearch(searchString)
            self.view.window?.makeFirstResponder(self)
        }
    }
    
    func updateSearchFilters() {
        var tokens = searchField.stringValue.count == 0 ? [SearchToken: String]() : viewModel.searchTokens
        
        let accountValue = tokens[.accountMatches] ?? ""
        let accountIndex = accountsDropdown.items.index(of: accountValue) ?? 0
        if accountsDropdown.selectedIndex != accountIndex {
            accountsDropdown.updateSelectedIndex(accountIndex)
        }
        
        let categoryValue = tokens[.categoryMatches] ?? ""
        let categoryIndex = categoriesDropdown.items.index(of: categoryValue) ?? 0
        if categoriesDropdown.selectedIndex != categoryIndex {
            categoriesDropdown.updateSelectedIndex(categoryIndex)
        }
        
        let whenValue = tokens[.when] ?? ""
        let whenIndex = timeDropdown.items.index(of: whenValue) ?? 0
        if timeDropdown.selectedIndex != whenIndex {
            timeDropdown.updateSelectedIndex(whenIndex)
        }
        
        let overString = tokens[.over]
        let underString = tokens[.under]
        var amountIndex = -1
        if overString == nil && underString == nil {
            amountIndex = 0
        } else if overString == nil && underString == "$10" {
            amountIndex = 1
        } else if overString == nil && underString == "$100" {
            amountIndex = 2
        } else if overString == "$500" && underString == nil {
            amountIndex = 3
        } else if overString == "$100" && underString == "$500" {
            amountIndex = 4
        }
        
        if amountIndex >= 0 {
            if amountDropdown.selectedIndex != amountIndex {
                amountDropdown.updateSelectedIndex(amountIndex)
                amountDropdown.overrideColor = false
            }
        } else if overString != nil || underString != nil {
            let overCents = overString == nil ? viewModel.minTransactionAmount : stringToCents(overString!)
            let underCents = underString == nil ? viewModel.maxTransactionAmount : stringToCents(underString!)
            if let overCents = overCents, let underCents = underCents {
                amountDropdown.selectedIndex = -1
                amountDropdown.overrideColor = true
                amountDropdown.titleLabel.stringValue = "\(centsToString(overCents, showCents: false)) - \(centsToString(underCents, showCents: false))"
            }
        }
    }

    func showSearch() {
        self.view.window?.makeFirstResponder(searchField)
        searchField.textField.currentEditor()?.moveToEndOfLine(nil)
    }

    func performSearch(_ searchString: String) {
        searchField.attributedStringValue = Search.styleSearchString(searchString)
        performSearchNow()
    }
    
    override func controlTextDidChange(_ obj: Notification) {
        searchField.attributedStringValue = Search.styleSearchString(searchField.stringValue)
        if searchField.attributedStringValue.string.count == 0 {
            updateSearchFilters()
        } else {
            showSearchFilters()
        }
        
        performSearchDelayed()
    }
    
    fileprivate let searchDelay: Double = 0.25
    func performSearchDelayed() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(performSearchNow), object: nil)
        self.perform(#selector(performSearchNow), with: nil, afterDelay: searchDelay)
    }
    
    @objc func performSearchNow() {
        showSearchFilters()
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(performSearchNow), object: nil)
        
        if previousSelectedIndex.section >= 0 {
            tableView.deselectIndex(previousSelectedIndex)
            tableView.noteHeightOfIndex(previousSelectedIndex)
            previousSelectedIndex = TableIndex.none
            NotificationCenter.postOnMainThread(name: InternalNotifications.CellClosed)
        }
        
        // Perform the search
        let searchString = searchField.stringValue
        let lastSearchTokens = viewModel.searchTokens
        let lastSearch = viewModel.lastSearch
        viewModel.performSearchNow(searchString: searchString)
        
        if searchString.isEmpty {
            hideSearchFilters()
            if lastSearchTokens.count > 0 {
                updateSearchFilters()
            }
        } else {
            if lastSearchTokens != viewModel.searchTokens {
                updateSearchFilters()
            }
        }
        
        updateNumberOfTransactionsAndTotal()
        
        tableView.updateRows(oldObjects: lastSearch.flattened as NSArray, newObjects: viewModel.data.flattened as NSArray, animationOptions: [NSTableView.AnimationOptions.effectFade, NSTableView.AnimationOptions.slideDown])
        
        tableView.scrollToBeginningOfDocument(nil)

        if viewModel.searching && viewModel.data.count > 0 {
            scrollView.contentInsets = NSEdgeInsetsMake(0, 0, 30, 0)
            footerView.snp.updateConstraints { make in
                make.height.equalTo(32)
            }
        } else {
            scrollView.contentInsets = NSEdgeInsetsZero
            footerView.snp.updateConstraints { make in
                make.height.equalTo(0)
            }
        }
        self.view.layoutSubtreeIfNeeded()
    }
    
    func updateNumberOfTransactionsAndTotal() {
//        var runningTotal: Int = 0
//        var numberOfTransactions: Int = 0
//        for date in viewModel.data.keys {
//            if let transactions = viewModel.data[date] {
//                for transaction in transactions {
//                    runningTotal = runningTotal + transaction.amount
//                    numberOfTransactions += 1
//                }
//            }
//        }
//
//        totalField.attributedStringValue = centsToStringFormatted(runningTotal, showNegative: false, showCents: true, colorPositive: false)
//        transactionCountField.stringValue = "\(numberOfTransactions) TRANSACTIONS"
    }
    
    fileprivate var searchShortcutMonitor: AnyObject?
    
    // Command + F to activate search
    func addSearchShortcutMonitor() {
        if searchShortcutMonitor == nil {
            searchShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: NSEvent.EventTypeMask.keyDown) { event -> NSEvent? in
                if event.window == self.view.window {
                    if let characters = event.charactersIgnoringModifiers {
                        if event.modifierFlags.contains(NSEvent.ModifierFlags.command) && characters.count == 1 {
                            if characters == "f" {
                                self.view.window?.makeFirstResponder(self.searchField)
                                return nil
                            }
                        }
                    }
                }
                
                return event
            } as AnyObject?
        }
    }
    
    func removeSearchShortcutMonitor() {
        if let monitor = searchShortcutMonitor {
            NSEvent.removeMonitor(monitor)
            searchShortcutMonitor = nil
        }
    }

    //
    // MARK: - Table View -
    //
    
    func tableView(_ tableView: SectionedTableView, hoveredIndex: TableIndex, lastHoveredIndex: TableIndex) {
        // Cancel any queued loads
        hoverPreloadWorkItem?.cancel()
        
        // If we hover over a cell when it has a location and is not already opened, preload the map
        if hoveredIndex != previousSelectedIndex, let hoveredCell = tableView.viewAtIndex(hoveredIndex, makeIfNecessary: false) as? TransactionsTabTransactionCell {//}, let model = hoveredCell.model{
            // Add a small delay to allow for canceling preload when quickly moving mouse
            hoverPreloadWorkItem = DispatchWorkItem {
                hoveredCell.loadBottomContainer()
            }
            async(after: 0.2, execute: hoverPreloadWorkItem!)
        }
        
        // If we are no longer hovering over a cell when it has a location and is not already opened, unload the map to save memory
        if lastHoveredIndex != previousSelectedIndex, let lastHoveredCell = tableView.viewAtIndex(lastHoveredIndex, makeIfNecessary: false) as? TransactionsTabTransactionCell {//}, let model = lastHoveredCell.model, model.hasLocation {
            lastHoveredCell.unloadBottomContainer()
        }
    }

    func tableView(_ tableView: SectionedTableView, clickedRow row: Int, inSection section: Int) {
        // Click to expand not yet supported
        return
    }
    
    func numberOfSectionsInTableView(_ tableView: SectionedTableView) -> Int {
        return viewModel.numberOfSections()
    }
    
    func tableView(_ tableView: SectionedTableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel.numberOfRows(inSection: section)
    }
    
    func tableView(_ tableView: SectionedTableView, heightOfSection section: Int) -> CGFloat {
        return CurrentTheme.transactions.headerCell.height
    }
    
    func tableView(_ tableView: SectionedTableView, heightOfRow row: Int, inSection section: Int) -> CGFloat {
        if TableIndex(section: section, row: row) == tableView.selectedIndex, let transactions = viewModel.data[section] {
            let transaction = transactions[row]
            var extraHeight: CGFloat = 0.0
//            if transaction.hasLocation {
//                extraHeight = 212.0 + 32
//            } else {
                if transaction.categoryId == nil {
                    extraHeight = 63.0 + 32
                } else {
                    extraHeight = 90.0 + 32
                }
//            }
            return CurrentTheme.transactions.cell.height + extraHeight
        } else {
            return CurrentTheme.transactions.cell.height
        }
    }
    
    func tableView(_ tableView: SectionedTableView, rowViewForSection section: Int) -> NSTableRowView? {
        var row = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "Date Row"), owner: self) as? NSTableRowView
        if row == nil {
            row = TableRowView()
            row?.identifier = NSUserInterfaceItemIdentifier(rawValue: "Date Row")
        }
        return row
    }
    
    func tableView(_ tableView: SectionedTableView, rowViewForRow row: Int, inSection section: Int) -> NSTableRowView? {
        var row = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "Transaction Row"), owner: self) as? HoverTableRowView
        if row == nil {
            row = HoverTableRowView()
            row?.identifier = NSUserInterfaceItemIdentifier(rawValue: "Transaction Row")
            row?.color = NSColor.clear
            row?.hoverColor = NSColor.clear
        }
        return row
    }

    func tableView(_ tableView: SectionedTableView, viewForSection section: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "Group Cell"), owner: self) as? TransactionsTabGroupCell ?? TransactionsTabGroupCell()
        cell.identifier = NSUserInterfaceItemIdentifier(rawValue: "Group Cell")
        cell.section = -1
        
        let sectionTitle = viewModel.sectionTitle(for: section)
        cell.updateModel(sectionTitle)
        
        return cell
    }
    
    func tableView(_ tableView: SectionedTableView, viewForRow row: Int, inSection section: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "Transaction Cell"), owner: self) as? TransactionsTabTransactionCell ?? TransactionsTabTransactionCell()
        cell.identifier = NSUserInterfaceItemIdentifier(rawValue: "Transaction Cell")
        
        if previousSelectedIndex != TableIndex.none && cell.index == previousSelectedIndex {
            cell.hideBottomContainer()
            tableView.deselectIndex(previousSelectedIndex)
            tableView.noteHeightOfIndex(previousSelectedIndex)
            async(after: 0.3) {
                tableView.reloadData()
            }
            previousSelectedIndex = TableIndex.none
        }
        
        if let transaction = viewModel.transaction(forRow: row, inSection: section) {
            cell.updateModel(transaction)
            cell.index = TableIndex(section: section, row: row)
            
            let selectedIndex = tableView.selectedIndex
            if selectedIndex != TableIndex.none {
                cell.alphaValue = cell.index == selectedIndex ? 1.0 : CurrentTheme.transactions.cell.dimmedAlpha
            }
        } else {
            log.error("Couldn't find transaction for row \(row) in section \(section)")
        }
        
        return cell
    }
}

