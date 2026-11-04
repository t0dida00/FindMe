import Foundation
import Supabase

/// Maps Postgres `raise exception '<code>'` texts, redeem_code error codes and transport errors
/// to friendly (localized, Vietnamese-first) messages.
enum AppError {
    static func message(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return String(localized: "Không có kết nối mạng. Vui lòng thử lại.")
            case .timedOut:
                return String(localized: "Mạng quá chậm, yêu cầu đã hết thời gian chờ.")
            case .cancelled:
                return String(localized: "Đã hủy.")
            default:
                return String(localized: "Lỗi kết nối. Vui lòng thử lại.")
            }
        }
        if let go = error as? GoAPI.Failure {
            if let m = message(code: go.code) { return m }
            return goMessage(code: go.code, status: go.status)
        }
        if let pg = error as? PostgrestError {
            if let m = message(code: pg.message) { return m }
            // e.g. 'new row … violates check constraint "games_public_needs_area"'
            for code in knownCodes where pg.message.contains(code) {
                if let m = message(code: code) { return m }
            }
            return pg.message
        }
        if let auth = error as? AuthError {
            return String(localized: "Đăng nhập thất bại: \(auth.localizedDescription)")
        }
        if let storage = error as? StorageError {
            return String(localized: "Lỗi tải ảnh: \(storage.message)")
        }
        let text = String(describing: error)
        for code in knownCodes where text.contains(code) {
            if let m = message(code: code) { return m }
        }
        return error.localizedDescription
    }

    /// Codes only the Go API returns (HTTP-level), by code then by status.
    static func goMessage(code: String, status: Int) -> String {
        switch code {
        case "rate_limited", "too_many_streams": return String(localized: "Bạn thao tác quá nhanh, thử lại sau giây lát.")
        case "timeout", "canceled": return String(localized: "Máy chủ phản hồi chậm, vui lòng thử lại.")
        case "invalid_join_code": return String(localized: "Mã tham gia gồm 6 chữ hoặc số.")
        case "forbidden": return String(localized: "Bạn không có quyền làm việc này.")
        default: break
        }
        switch status {
        case 401: return String(localized: "Bạn cần đăng nhập lại.")
        case 404: return String(localized: "Không tìm thấy dữ liệu.")
        case 413, 422: return String(localized: "Dữ liệu không hợp lệ.")
        default: return String(localized: "Máy chủ gặp lỗi, vui lòng thử lại.")
        }
    }

    static let knownCodes = [
        "not_authenticated", "game_not_found", "hint_not_found", "not_a_player", "hint_not_active",
        "submission_not_found", "submission_not_reserved", "submission_not_pending", "invalid_photo_path",
        "not_game_staff", "not_game_host", "game_not_editable", "game_not_cancellable",
        "game_not_startable", "game_has_no_hints", "code_too_short", "hint_title_required", "hint_location_locked", "hint_order_locked", "invalid_role",
        "participant_not_found", "wrong_code", "code_entry_locked", "code_in_use",
        "upload_window_expired", "game_not_finished", "not_game_player", "invalid_stars", "games_public_needs_area", "already_in_active_game",
        "game_full", "max_players_below_count", "last_hint", "hint_prize_over_grand", "grand_prize_below_hint", "game_not_open", "game_closed",
        "duplicate key value",
    ]

    static func message(code raw: String) -> String? {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch code {
        case "not_authenticated": return String(localized: "Bạn cần đăng nhập lại.")
        case "game_not_found": return String(localized: "Không tìm thấy game với mã này, hoặc game đã kết thúc.")
        case "hint_not_found": return String(localized: "Không tìm thấy hint.")
        case "game_not_finished": return String(localized: "Chỉ chấm điểm được khi game đã kết thúc.")
        case "not_game_player": return String(localized: "Chỉ người chơi của game mới chấm điểm được.")
        case "invalid_stars": return String(localized: "Số sao phải từ 1 đến 5.")
        case "already_in_active_game": return String(localized: "Bạn đang ở trong một game chưa kết thúc. Mỗi người chỉ tham gia hoặc tổ chức 1 game tại một thời điểm.")
        case "game_full": return String(localized: "Game đã đủ người chơi.")
        case "max_players_below_count": return String(localized: "Giới hạn không được thấp hơn số người chơi đã tham gia.")
        case "games_public_needs_area": return String(localized: "Ghim khu vực để công khai game.")
        case "not_a_player": return String(localized: "Chỉ người chơi mới được nhập mã. Quản trò không thể tham gia giải hint.")
        case "hint_not_active": return String(localized: "Hint này không còn mở (đã có người giải hoặc game đã dừng).")
        case "submission_not_found": return String(localized: "Không tìm thấy lượt nộp mã.")
        case "submission_not_reserved": return String(localized: "Lượt giữ mã đã hết hạn hoặc đã được xử lý.")
        case "submission_not_pending": return String(localized: "Mã này đã được xử lý.")
        case "invalid_photo_path": return String(localized: "Đường dẫn ảnh không hợp lệ.")
        case "not_game_staff": return String(localized: "Bạn không phải quản trò của game này.")
        case "not_game_host": return String(localized: "Chỉ quản trò chính mới làm được việc này.")
        case "game_not_editable": return String(localized: "Game đã bắt đầu, không thể chỉnh sửa nữa.")
        case "game_not_cancellable": return String(localized: "Game đã kết thúc, không thể hủy.")
        case "game_not_startable": return String(localized: "Game không thể bắt đầu ở trạng thái hiện tại.")
        case "game_has_no_hints": return String(localized: "Cần ít nhất một hint trước khi hẹn giờ hoặc bắt đầu.")
        case "game_closed": return String(localized: "Game này đã kết thúc hoặc đã bị hủy.")
        case "game_not_open": return String(localized: "Game này cần mã tham gia. Xin mã 6 ký tự từ quản trò.")
        case "hint_prize_over_grand": return String(localized: "Thưởng mốc không được lớn hơn giải thưởng tổng.")
        case "grand_prize_below_hint": return String(localized: "Giải thưởng tổng không được nhỏ hơn thưởng mốc của hint.")
        case "last_hint": return String(localized: "Mỗi game cần ít nhất một hint, không thể xóa hint cuối cùng.")
        case "code_too_short": return String(localized: "Mã phải có ít nhất 6 chữ hoặc số.")
        case "hint_location_locked": return String(localized: "Không đổi được vị trí đáp án khi game đã bắt đầu.")
        case "hint_order_locked": return String(localized: "Không đổi được thứ tự hint khi game đã bắt đầu.")
        case "hint_title_required": return String(localized: "Hint cần có tiêu đề.")
        case "invalid_role": return String(localized: "Vai trò không hợp lệ.")
        case "participant_not_found": return String(localized: "Không tìm thấy người chơi này.")
        case "wrong_code": return String(localized: "Sai mã.")
        case "code_entry_locked": return String(localized: "Bạn đang bị khóa nhập mã.")
        case "code_in_use": return String(localized: "Có người đang xác minh mã này")
        case "upload_window_expired": return String(localized: "Đã quá thời hạn tải ảnh.")
        default:
            if code.contains("duplicate key value") {
                return String(localized: "Thứ tự này đã được dùng. Hãy chọn số khác.")
            }
            return nil
        }
    }
}
