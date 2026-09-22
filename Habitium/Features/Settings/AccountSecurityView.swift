//
//  AccountSecurityView.swift
//  Habitium
//
//  Ajustes → Seguridad → Verificación en dos pasos, y cambio de
//  contraseña sin pasar por el correo.
//
//  Por qué esto importa más que ninguna otra medida: Row Level Security
//  (supabase/schema.sql) impide que una cuenta vea los datos de otra, y
//  eso está resuelto. Lo que RLS no puede impedir es que alguien entre
//  siendo tú. Si averigua tu contraseña —porque la reutilizabas en otro
//  sitio que tuvo una filtración, que es como pasa el 90% de las veces—
//  para el servidor es una sesión legítima y le enseña todo. La
//  verificación en dos pasos es lo único que corta eso.
//
//  Detalle de diseño que parece un rodeo y no lo es: el alta va en dos
//  tiempos (primero el secreto, después confirmarlo con un código). Si se
//  activara de golpe y la app de códigos no lo hubiera guardado bien, te
//  quedarías fuera de tu propia cuenta sin forma de volver a entrar.
//
//  Y por qué NO hay código QR aquí: un QR habría que escanearlo con otro
//  aparato. En el móvil es mejor el enlace `otpauth://`, que abre la app
//  de códigos de este mismo teléfono de un toque. Quien prefiera
//  escanearlo tiene el QR en la versión web.
//

import Auth
import SwiftUI

struct AccountSecurityView: View {
    @Environment(SupabaseAuthManager.self) private var emailAuth
    @Environment(\.openURL) private var openURL

    @State private var factores: [Factor] = []
    @State private var cargando = true

    /// El alta a medias: existe mientras se está configurando.
    @State private var alta: SupabaseAuthManager.Enrollment?
    @State private var codigo = ""
    @State private var mensaje: String?
    @State private var mensajeEsBueno = false

    @State private var contrasenaNueva = ""
    @State private var contrasenaRepetida = ""

    private var activa: Bool { !factores.isEmpty }

    var body: some View {
        List {
            estadoSection
            if alta != nil { altaSection } else if !activa { activarSection }
            if activa && alta == nil { desactivarSection }
            contrasenaSection
            if let mensaje {
                Section {
                    Text(mensaje)
                        .font(.footnote)
                        .foregroundStyle(mensajeEsBueno ? Theme.Colors.nutrition : Theme.Colors.danger)
                }
            }
        }
        .navigationTitle("Verificación en dos pasos")
        .navigationBarTitleDisplayMode(.inline)
        .task { await recargar() }
    }

    // MARK: - Secciones

    private var estadoSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: activa ? "lock.shield.fill" : "lock.open")
                    .font(.title2)
                    .foregroundStyle(activa ? Theme.Colors.nutrition : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cargando ? "Comprobando…" : (activa ? "Activada" : "Desactivada"))
                        .font(.subheadline.bold())
                    Text(activa
                         ? "Para entrar hacen falta tu contraseña y el código de tu móvil."
                         : "Ahora mismo basta con tu contraseña para entrar en tu cuenta.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var activarSection: some View {
        Section {
            Button {
                Task {
                    mensaje = nil
                    alta = await emailAuth.enrollSecondFactor()
                    if alta == nil { fallo(emailAuth.errorMessage ?? "No se ha podido empezar.") }
                }
            } label: {
                Label("Activar verificación en dos pasos", systemImage: "lock.shield")
            }
            .disabled(cargando)
        } footer: {
            Text("Necesitas una app de códigos en el móvil: Google Authenticator, Authy, 2FAS o la propia app Contraseñas del iPhone, que ya la trae de serie.")
        }
    }

    private var altaSection: some View {
        Section {
            if let alta, !alta.uri.isEmpty {
                Button {
                    if let url = URL(string: alta.uri) { openURL(url) }
                } label: {
                    Label("Añadirlo a mi app de códigos", systemImage: "arrow.up.forward.app")
                }
            }

            if let alta, !alta.secret.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("O escríbelo a mano")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(alta.secret)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            TextField("Código de seis cifras", text: $codigo)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.system(.title3, design: .monospaced))
                .onChange(of: codigo) { _, nuevo in
                    codigo = String(nuevo.filter(\.isNumber).prefix(6))
                }

            Button("Confirmar y activar") {
                Task { await confirmar() }
            }
            .disabled(codigo.count < 6)

            Button("Cancelar", role: .cancel) {
                Task { await cancelarAlta() }
            }
        } header: {
            Text("Últimos dos pasos")
        } footer: {
            Text("Añade el código a tu app, espera a que te dé un número de seis cifras y escríbelo aquí. Hasta que no lo confirmes no se activa nada — así no hay manera de quedarte fuera por un despiste.")
        }
    }

    private var desactivarSection: some View {
        Section {
            Button("Desactivar", role: .destructive) {
                Task {
                    guard let id = factores.first?.id else { return }
                    await emailAuth.removeSecondFactor(factorId: id)
                    if let error = emailAuth.errorMessage { fallo(error) } else { bien("Desactivada.") }
                    await recargar()
                }
            }
        } footer: {
            Text("Sin ella, quien sepa tu contraseña entra en tu cuenta.")
        }
    }

    private var contrasenaSection: some View {
        Section {
            SecureField("Contraseña nueva (mínimo 10)", text: $contrasenaNueva)
            SecureField("Repítela", text: $contrasenaRepetida)
            Button("Cambiar contraseña") {
                Task { await cambiarContrasena() }
            }
            .disabled(contrasenaNueva.count < 10 || contrasenaNueva != contrasenaRepetida)
        } header: {
            Text("Cambiar la contraseña")
        } footer: {
            Text("Diez caracteres o más. Una frase corta que solo tú digas es mucho más difícil de romper que ocho letras con un símbolo al final — y no se te olvida.")
        }
    }

    // MARK: - Acciones

    private func recargar() async {
        cargando = true
        factores = await emailAuth.secondFactors()
        cargando = false
    }

    private func confirmar() async {
        guard let alta else { return }
        if await emailAuth.confirmSecondFactor(factorId: alta.id, code: codigo) {
            self.alta = nil
            codigo = ""
            await recargar()
            bien("Listo. A partir de ahora te pedirá el código al entrar.")
        } else {
            fallo(emailAuth.errorMessage ?? "Ese código no es válido.")
            codigo = ""
        }
    }

    private func cancelarAlta() async {
        // Cancelar tiene que DESHACERLO en el servidor. Si solo se cerrara
        // la pantalla quedaría un factor a medias dando guerra la próxima
        // vez que se intente activar.
        if let alta { await emailAuth.removeSecondFactor(factorId: alta.id) }
        alta = nil
        codigo = ""
        mensaje = nil
        await recargar()
    }

    private func cambiarContrasena() async {
        guard contrasenaNueva == contrasenaRepetida else {
            return fallo("Las dos contraseñas no son iguales.")
        }
        if await emailAuth.changePassword(to: contrasenaNueva) {
            contrasenaNueva = ""
            contrasenaRepetida = ""
            bien("Contraseña cambiada.")
        } else {
            fallo(emailAuth.errorMessage ?? "No se ha podido cambiar.")
        }
    }

    private func bien(_ texto: String) { mensaje = texto; mensajeEsBueno = true }
    private func fallo(_ texto: String) { mensaje = texto; mensajeEsBueno = false }
}

#Preview {
    NavigationStack {
        AccountSecurityView()
            .environment(SupabaseAuthManager())
    }
}
