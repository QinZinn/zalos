#include "contact_model.h"
#include "text_fold.h"
#include <algorithm>

namespace Zalos::Core::Models {

ContactModel::ContactModel(QObject* parent)
    : QAbstractListModel(parent) {
}

int ContactModel::rowCount(const QModelIndex& parent) const {
    if (parent.isValid()) {
        return 0;
    }
    return m_filteredItems.size();
}

QVariant ContactModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_filteredItems.size()) {
        return QVariant();
    }

    const auto& item = m_filteredItems.at(index.row());
    switch (role) {
        case IdRole:
            return item.id;
        case NameRole:
            return item.name;
        case AvatarUrlRole:
            return item.avatarUrl;
        case IsOnlineRole:
            return item.isOnline;
        case IsGroupRole:
            return item.isGroup;
        case MemberCountRole:
            return item.memberCount;
        case CategoryRole:
            return item.category;
        case SubtitleRole:
            return item.subtitle;
        default:
            return QVariant();
    }
}

QHash<int, QByteArray> ContactModel::roleNames() const {
    return {
        {IdRole, "id"},
        {NameRole, "name"},
        {AvatarUrlRole, "avatarUrl"},
        {IsOnlineRole, "isOnline"},
        {IsGroupRole, "isGroup"},
        {MemberCountRole, "memberCount"},
        {CategoryRole, "category"},
        {SubtitleRole, "subtitle"}
    };
}

void ContactModel::recomputeCounts() {
    int friends = 0;
    int groups = 0;
    int invites = 0;
    for (const auto& item : m_allItems) {
        if (!item.isGroup && item.category == QLatin1String("friends")) ++friends;
        if (item.isGroup || item.category == QLatin1String("groups")) ++groups;
        if (item.category == QLatin1String("invites")) ++invites;
    }
    m_friendCount = friends;
    m_groupCount = groups;
    m_inviteCount = invites;
}

void ContactModel::setCategoryFilter(const QString& category) {
    if (m_activeCategory != category) {
        m_activeCategory = category;
        applyFilter();
        emit filterChanged();
    }
}

void ContactModel::setSearchFilter(const QString& query) {
    if (m_searchQuery != query) {
        m_searchQuery = query;
        applyFilter();
        emit filterChanged();
    }
}

namespace {
QVector<int> diffContactRoles(const ContactItem& a, const ContactItem& b) {
    QVector<int> roles;
    if (a.id != b.id) roles << ContactModel::IdRole;
    if (a.name != b.name) roles << ContactModel::NameRole;
    if (a.avatarUrl != b.avatarUrl) roles << ContactModel::AvatarUrlRole;
    if (a.isOnline != b.isOnline) roles << ContactModel::IsOnlineRole;
    if (a.isGroup != b.isGroup) roles << ContactModel::IsGroupRole;
    if (a.memberCount != b.memberCount) roles << ContactModel::MemberCountRole;
    if (a.category != b.category) roles << ContactModel::CategoryRole;
    if (a.subtitle != b.subtitle) roles << ContactModel::SubtitleRole;
    return roles;
}
}

void ContactModel::publishFiltered(QVector<ContactItem> next) {
    QVector<ContactItem>& cur = m_filteredItems;
    if (cur.isEmpty() || next.isEmpty()) {
        beginResetModel();
        cur = std::move(next);
        endResetModel();
        return;
    }
    QSet<QString> curIds;
    curIds.reserve(cur.size());
    for (const auto& item : cur) {
        if (item.id.isEmpty() || curIds.contains(item.id)) {
            beginResetModel();
            cur = std::move(next);
            endResetModel();
            return;
        }
        curIds.insert(item.id);
    }
    QSet<QString> nextIds;
    nextIds.reserve(next.size());
    for (const auto& item : next) {
        if (item.id.isEmpty() || nextIds.contains(item.id)) {
            beginResetModel();
            cur = std::move(next);
            endResetModel();
            return;
        }
        nextIds.insert(item.id);
    }

    int i = cur.size() - 1;
    while (i >= 0) {
        if (nextIds.contains(cur[i].id)) {
            --i;
            continue;
        }
        const int end = i;
        while (i > 0 && !nextIds.contains(cur[i - 1].id)) --i;
        beginRemoveRows(QModelIndex(), i, end);
        cur.remove(i, end - i + 1);
        endRemoveRows();
        --i;
    }

    QSet<QString> remainingIds;
    remainingIds.reserve(cur.size());
    for (const auto& item : cur) remainingIds.insert(item.id);

    for (int pos = 0; pos < next.size();) {
        if (pos < cur.size() && cur[pos].id == next[pos].id) {
            const QVector<int> roles = diffContactRoles(cur[pos], next[pos]);
            cur[pos] = std::move(next[pos]);
            if (!roles.isEmpty()) emit dataChanged(index(pos), index(pos), roles);
            ++pos;
            continue;
        }
        int found = -1;
        for (int j = pos + 1; j < cur.size(); ++j) {
            if (cur[j].id == next[pos].id) {
                found = j;
                break;
            }
        }
        if (found >= 0) {
            beginMoveRows(QModelIndex(), found, found, QModelIndex(), pos);
            cur.move(found, pos);
            endMoveRows();
            const QVector<int> roles = diffContactRoles(cur[pos], next[pos]);
            cur[pos] = std::move(next[pos]);
            if (!roles.isEmpty()) emit dataChanged(index(pos), index(pos), roles);
            ++pos;
            continue;
        }
        int insertEnd = pos + 1;
        while (insertEnd < next.size() && !remainingIds.contains(next[insertEnd].id)) ++insertEnd;
        const int count = insertEnd - pos;
        beginInsertRows(QModelIndex(), pos, insertEnd - 1);
        cur.insert(pos, count, ContactItem{});
        for (int k = 0; k < count; ++k) cur[pos + k] = std::move(next[pos + k]);
        endInsertRows();
        pos = insertEnd;
    }
}

void ContactModel::applyFilter() {
    QVector<ContactItem> next;
    const QStringList terms = foldTerms(m_searchQuery);
    const bool hasQuery = !m_searchQuery.isEmpty();
    for (const auto& item : m_allItems) {
        const bool matchesCategory = m_activeCategory.isEmpty() || (item.category == m_activeCategory);
        if (!matchesCategory) continue;
        const bool matchesSearch = !hasQuery
            || (terms.isEmpty() ? item.name.contains(m_searchQuery, Qt::CaseInsensitive)
                                : containsAllTerms(item.foldedName, terms));
        if (matchesSearch) next.append(item);
    }

    publishFiltered(std::move(next));
    emit countChanged();
}

void ContactModel::addContact(const ContactItem& item) {
    ContactItem copy = item;
    if (copy.foldedName.isEmpty()) copy.foldedName = foldForSearch(copy.name);
    auto pos = std::lower_bound(m_allItems.begin(), m_allItems.end(), copy, [](const ContactItem& a, const ContactItem& b) {
        return a.name.localeAwareCompare(b.name) < 0;
    });
    m_allItems.insert(pos, std::move(copy));
    recomputeCounts();
    applyFilter();
}

void ContactModel::setContacts(const QVector<ContactItem>& items) {
    m_allItems = items;
    for (auto& item : m_allItems) {
        if (item.foldedName.isEmpty()) item.foldedName = foldForSearch(item.name);
    }
    std::stable_sort(m_allItems.begin(), m_allItems.end(), [](const ContactItem& a, const ContactItem& b) {
        return a.name.localeAwareCompare(b.name) < 0;
    });
    recomputeCounts();
    applyFilter();
}

void ContactModel::setOnlineIds(const QSet<QString>& ids) {
    for (auto& item : m_allItems) item.isOnline = ids.contains(item.id);
    for (int row = 0; row < m_filteredItems.size(); ++row) {
        const bool online = ids.contains(m_filteredItems[row].id);
        if (m_filteredItems[row].isOnline != online) {
            m_filteredItems[row].isOnline = online;
            emit dataChanged(index(row), index(row), {IsOnlineRole});
        }
    }
}

void ContactModel::clearAll() {
    beginResetModel();
    m_allItems.clear();
    m_filteredItems.clear();
    m_friendCount = 0;
    m_groupCount = 0;
    m_inviteCount = 0;
    endResetModel();
    emit countChanged();
}

}
