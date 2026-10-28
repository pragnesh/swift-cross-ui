/// A built-in picker style backed by a backend-supported picker widget.
public protocol _BuiltinPickerStyle {
    @MainActor
    func _asBackendPickerStyle<Backend: BaseAppBackend>(backend: Backend) -> BackendPickerStyle
}

extension PickerStyle where Self: _BuiltinPickerStyle {
    public func makeView<Value: Equatable>(
        options: [Value],
        selection: Binding<Value?>,
        environment: EnvironmentValues
    ) -> _BuiltinPickerImplementation {
        _BuiltinPickerImplementation(
            style: self._asBackendPickerStyle(backend: environment.backend),
            options: options.map { "\($0)" },
            selectedIndex: Binding {
                selection.wrappedValue.flatMap(options.firstIndex(of:))
            } set: { index in
                guard let index else {
                    selection.wrappedValue = nil
                    return
                }
                // Backends can report an index while their options are being
                // replaced; ignore one that doesn't fit these options.
                guard options.indices.contains(index) else { return }
                selection.wrappedValue = options[index]
            }
        )
    }

    public func isSupported<Backend: BaseAppBackend>(backend: Backend) -> Bool {
        backend.supportedPickerStyles.contains(_asBackendPickerStyle(backend: backend))
    }
}
