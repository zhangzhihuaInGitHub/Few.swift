//
//  Component.swift
//  Few
//
//  Created by Josh Abernathy on 8/1/14.
//  Copyright (c) 2014 Josh Abernathy. All rights reserved.
//

import Foundation
import CoreGraphics
import SwiftBox

/// Components are stateful elements and the bridge between Few and
/// AppKit/UIKit.
///
/// Simple components can be created without subclassing. More complex
/// components will need to subclass it in order to add lifecycle events or 
/// customize its behavior further.
///
/// By default whenever the component's state is changed, it re-renders itself 
/// by calling the `render` function passed in to its init. But subclasses can
/// optimize this by implementing `componentShouldRender`.
public class Component<S>: Element {
	/// The state on which the component depends.
	private var state: S

	private var rootElement: Element?

	private let renderFn: ((Component, S) -> Element)?

	private var renderQueued: Bool = false

	/// Initializes the component with its initial state. The render function
	/// takes the current state of the component and returns the element which 
	/// represents that state.
	public init(initialState: S) {
		self.state = initialState
		super.init()
	}

	public init(render: (Component, S) -> Element, initialState: S) {
		self.renderFn = render
		self.state = initialState
		super.init()
	}

	// MARK: Lifecycle

	public func render(state: S) -> Element {
		if let renderFn = renderFn {
			return renderFn(self, state)
		} else {
			return Empty()
		}
	}

	final private func render() {
		if let rootElement = rootElement {
			renderWithOldRoot(rootElement, defaultFrame: rootElement.frame)
		}
	}

	final private func realizeNewRoot(newRoot: Element) {
		newRoot.realize()

		configureViewToAutoresize(newRoot.view!)
		view = newRoot.view!
	}

	final private func renderWithOldRoot(root: Element?, defaultFrame: CGRect) {
		let newRoot = render(state)
		newRoot.frame = defaultFrame

		let node = newRoot.assembleLayoutNode()
		let layout = node.layout()
		println(layout)
		newRoot.applyLayout(layout)

		if let root = root {
			if newRoot.canDiff(root) {
				newRoot.applyDiff(root)
			} else {
				let superview = root.view!.superview
				root.derealize()

				realizeNewRoot(newRoot)
				superview!.addSubview(newRoot.view!)
			}

			componentDidRender()
		} else {
			componentWillRealize()
			realizeNewRoot(newRoot)
			componentDidRealize()
		}

		rootElement = newRoot
	}

	/// Render the component without changing any state.
	final public func forceRender() {
		enqueueRender()
	}
	
	/// Called when the component will be realized and before the component is
	/// rendered for the first time.
	public func componentWillRealize() {}
	
	/// Called when the component has been realized and after the component has
	/// been rendered for the first time.
	public func componentDidRealize() {}
	
	/// Called when the component is about to be derealized.
	public func componentWillDerealize() {}
	
	/// Called when the component has been derealized.
	public func componentDidDerealize() {}
	
	/// Called after the component has been rendered and diff applied.
	public func componentDidRender() {}
	
	/// Called when the state has changed but before the component is 
	/// re-rendered. This gives the component the chance to decide whether it 
	/// *should* based on the new state.
	///
	/// The default implementation always returns true.
	public func componentShouldRender(previousState: S, newState: S) -> Bool {
		return true
	}
	
	// MARK: -

	/// Add the component to the given view. A component can only be added to 
	/// one view at a time.
	public func addToView(hostView: ViewType) {
		renderWithOldRoot(nil, defaultFrame: hostView.bounds)
		hostView.addSubview(rootElement!.view!)
	}

	/// Remove the component from its host view.
	public func remove() {
		derealize()
	}
	
	/// Update the state using the given function.
	final public func updateState(fn: S -> S) {
		precondition(NSThread.isMainThread(), "Component.updateState called on a background thread. Donut do that!")

		let oldState = state
		state = fn(oldState)
		
		if componentShouldRender(oldState, newState: state) {
			enqueueRender()
		}
	}

	final private func enqueueRender() {
		if renderQueued { return }

		renderQueued = true

		let observer = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, CFRunLoopActivity.Exit.rawValue, 0, 0) { _, _ in
			self.renderQueued = false
			self.render()
		}
		CFRunLoopAddObserver(CFRunLoopGetMain(), observer, kCFRunLoopDefaultMode)
	}

	/// Get the current state of the component.
	final public func getState() -> S {
		return state
	}
	
	// MARK: Element
	
	public override func applyDiff(old: Element) {
		super.applyDiff(old)

		// Use `unsafeBitCast` instead of `as` to avoid a runtime crash.
		let oldComponent = unsafeBitCast(old, Component.self)

		if let rootElement = oldComponent.rootElement {
			renderWithOldRoot(rootElement, defaultFrame: rootElement.frame)
		}
	}
	
	public override func realize() {
		renderWithOldRoot(nil, defaultFrame: CGRectZero)
	}

	public override func derealize() {
		componentWillDerealize()

		rootElement?.derealize()
		rootElement = nil

		componentDidDerealize()
	}
}
