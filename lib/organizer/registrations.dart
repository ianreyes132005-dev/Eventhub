import 'package:flutter/material.dart';

// Organizer Registrations Screen Colors
const Color kBackground = Color(0xFFFBF6EA);
const Color kGold = Color(0xFFD6A742);
const Color kText = Color(0xFF111827);
const Color kSubText = Color(0xFF4B5563);

class RegistrationsScreen extends StatefulWidget {
  final bool showAsEmbedded;

  const RegistrationsScreen({super.key, this.showAsEmbedded = false});

  @override
  State<RegistrationsScreen> createState() => _RegistrationsScreenState();
}

class _RegistrationsScreenState extends State<RegistrationsScreen> {
  late TextEditingController _searchController;

  String _selectedFilter = 'All';
  String _searchQuery = '';

  // Mock data for registrations
  final List<Map<String, dynamic>> _allRegistrations = [
    {
      'id': 'REG001',
      'studentName': 'Sarah Johnson',
      'studentId': 'STU001',
      'eventName': 'Science Fair 2026',
      'registrationDate': 'Oct 10',
      'status': 'Confirmed',
    },
    {
      'id': 'REG002',
      'studentName': 'Michael Chen',
      'studentId': 'STU002',
      'eventName': 'Science Fair 2026',
      'registrationDate': 'Oct 12',
      'status': 'Pending',
    },
    {
      'id': 'REG003',
      'studentName': 'Emma Rodriguez',
      'studentId': 'STU003',
      'eventName': 'Regional Debate Finals',
      'registrationDate': 'Oct 08',
      'status': 'Checked In',
    },
    {
      'id': 'REG004',
      'studentName': 'James Wilson',
      'studentId': 'STU004',
      'eventName': 'Science Fair 2026',
      'registrationDate': 'Oct 14',
      'status': 'Confirmed',
    },
    {
      'id': 'REG005',
      'studentName': 'Olivia Martinez',
      'studentId': 'STU005',
      'eventName': 'Art & Music Festival',
      'registrationDate': 'Oct 15',
      'status': 'Pending',
    },
    {
      'id': 'REG006',
      'studentName': 'David Kumar',
      'studentId': 'STU006',
      'eventName': 'Science Fair 2026',
      'registrationDate': 'Oct 09',
      'status': 'Checked In',
    },
    {
      'id': 'REG007',
      'studentName': 'Sophia Lee',
      'studentId': 'STU007',
      'eventName': 'Regional Debate Finals',
      'registrationDate': 'Oct 11',
      'status': 'Confirmed',
    },
    {
      'id': 'REG008',
      'studentName': 'Lucas Thompson',
      'studentId': 'STU008',
      'eventName': 'Science Fair 2026',
      'registrationDate': 'Oct 13',
      'status': 'Pending',
    },
    {
      'id': 'REG009',
      'studentName': 'Ava Patel',
      'studentId': 'STU009',
      'eventName': 'Art & Music Festival',
      'registrationDate': 'Oct 16',
      'status': 'Confirmed',
    },
    {
      'id': 'REG010',
      'studentName': 'Noah Anderson',
      'studentId': 'STU010',
      'eventName': 'Regional Debate Finals',
      'registrationDate': 'Oct 07',
      'status': 'Checked In',
    },
    {
      'id': 'REG011',
      'studentName': 'Isabella Thompson',
      'studentId': 'STU011',
      'eventName': 'Science Fair 2026',
      'registrationDate': 'Oct 11',
      'status': 'Pending',
    },
    {
      'id': 'REG012',
      'studentName': 'Ethan Brooks',
      'studentId': 'STU012',
      'eventName': 'Art & Music Festival',
      'registrationDate': 'Oct 14',
      'status': 'Confirmed',
    },
  ];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredRegistrations {
    List<Map<String, dynamic>> filtered = _allRegistrations;

    // Apply status filter
    if (_selectedFilter != 'All') {
      filtered = filtered
          .where((reg) => reg['status'] == _selectedFilter)
          .toList();
    }

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((reg) {
        final query = _searchQuery.toLowerCase();
        return reg['studentName'].toLowerCase().contains(query) ||
            reg['studentId'].toLowerCase().contains(query) ||
            reg['eventName'].toLowerCase().contains(query) ||
            reg['id'].toLowerCase().contains(query);
      }).toList();
    }

    return filtered;
  }

  Map<String, int> get _stats {
    return {
      'Total': _allRegistrations.length,
      'Pending': _allRegistrations
          .where((reg) => reg['status'] == 'Pending')
          .length,
      'Confirmed': _allRegistrations
          .where((reg) => reg['status'] == 'Confirmed')
          .length,
      'Checked In': _allRegistrations
          .where((reg) => reg['status'] == 'Checked In')
          .length,
    };
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;

    if (widget.showAsEmbedded) {
      // Return just the content without Scaffold when embedded
      return SingleChildScrollView(
        child: Column(
          children: [
            // Header
            _buildHeader(),
            const SizedBox(height: 16),

            // Summary cards
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: _buildSummaryCards(stats),
            ),
            const SizedBox(height: 24),

            // Filter chips
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: _buildFilterChips(),
            ),
            const SizedBox(height: 16),

            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: _buildSearchBar(),
            ),
            const SizedBox(height: 24),

            // Registrations list
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: _filteredRegistrations.isEmpty
                  ? _buildEmptyState()
                  : _buildRegistrationsList(),
            ),
            const SizedBox(height: 24),
          ],
        ),
      );
    }

    // Return full screen with Scaffold when not embedded
    return Scaffold(
      backgroundColor: const Color(0xFFFBF6EA),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header
              _buildHeader(),
              const SizedBox(height: 16),

              // Summary cards
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: _buildSummaryCards(stats),
              ),
              const SizedBox(height: 24),

              // Filter chips
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: _buildFilterChips(),
              ),
              const SizedBox(height: 16),

              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: _buildSearchBar(),
              ),
              const SizedBox(height: 24),

              // Registrations list
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: _filteredRegistrations.isEmpty
                    ? _buildEmptyState()
                    : _buildRegistrationsList(),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // Header widget
  Widget _buildHeader() {
    if (widget.showAsEmbedded) {
      // Embedded header - just title and notification, centered
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SizedBox(width: 40), // Spacer for balance
            // Title
            const Text(
              'Registrations',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF111827),
                fontFamily: 'Poppins',
              ),
            ),
            const SizedBox(width: 40), // Spacer for balance
          ],
        ),
      );
    }

    // Full screen header with back button
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.arrow_back,
                color: Color(0xFF111827),
                size: 20,
              ),
            ),
          ),

          // Title
          const Text(
            'Registrations',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF111827),
              fontFamily: 'Poppins',
            ),
          ),

          const SizedBox(width: 40), // Spacer for balance
        ],
      ),
    );
  }

  // Summary cards widget
  Widget _buildSummaryCards(Map<String, int> stats) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildStatCard('Total\nRegistrations', stats['Total']!.toString()),
        _buildStatCard('Pending', stats['Pending']!.toString()),
        _buildStatCard('Confirmed', stats['Confirmed']!.toString()),
        _buildStatCard('Checked\nIn', stats['Checked In']!.toString()),
      ],
    );
  }

  Widget _buildStatCard(String label, String value) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF111827),
                fontFamily: 'Poppins',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF4B5563),
                fontWeight: FontWeight.w500,
                fontFamily: 'Poppins',
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // Filter chips widget
  Widget _buildFilterChips() {
    final filters = ['All', 'Pending', 'Confirmed', 'Checked In'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((filter) {
          bool isSelected = _selectedFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GestureDetector(
              onTap: () {
                setState(() => _selectedFilter = filter);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFD6A742) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: isSelected
                      ? null
                      : Border.all(color: const Color(0xFFE5E7EB), width: 1),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(0xFFD6A742).withOpacity(0.2),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: Text(
                  filter,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : const Color(0xFF4B5563),
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // Search bar widget
  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'Search by name, event, or ID',
        hintStyle: const TextStyle(
          color: Color(0xFF4B5563),
          fontSize: 14,
          fontFamily: 'Poppins',
        ),
        prefixIcon: const Icon(
          Icons.search,
          color: Color(0xFF4B5563),
          size: 20,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: Colors.white,
        suffixIcon: _searchController.text.isNotEmpty
            ? GestureDetector(
                onTap: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                child: const Icon(
                  Icons.close,
                  color: Color(0xFF4B5563),
                  size: 18,
                ),
              )
            : null,
      ),
      style: const TextStyle(
        color: Color(0xFF111827),
        fontSize: 14,
        fontFamily: 'Poppins',
      ),
    );
  }

  // Registrations list widget
  Widget _buildRegistrationsList() {
    return Column(
      children: _filteredRegistrations.map((registration) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: _buildRegistrationCard(registration),
        );
      }).toList(),
    );
  }

  // Registration card widget
  Widget _buildRegistrationCard(Map<String, dynamic> registration) {
    final status = registration['status'];
    final statusColor = _getStatusColor(status);
    final avatarColor = _getAvatarColor(registration['avatar']);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: Avatar, Name, Status
          Row(
            children: [
              // Avatar
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: avatarColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: Text(
                    registration['avatar'],
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Name and username
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      registration['studentName'],
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                        fontFamily: 'Poppins',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      registration['username'],
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF4B5563),
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ],
                ),
              ),

              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Event and registration info
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFBF6EA),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow(
                  'Event',
                  registration['eventName'],
                  const Color(0xFF111827),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoRow(
                        'Date',
                        registration['eventDate'],
                        const Color(0xFF4B5563),
                      ),
                    ),
                    Expanded(
                      child: _buildInfoRow(
                        'Registered',
                        registration['registrationDate'],
                        const Color(0xFF4B5563),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Action buttons
          Row(
            children: [
              if (status == 'Checked In')
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text(
                        'View Details',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF4B5563),
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ),
                  ),
                )
              else if (status == 'Pending')
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      // TODO: Connect to backend to confirm registration
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Confirmed ${registration['studentName']}',
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD6A742),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Text(
                          'Confirm',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else if (status == 'Confirmed')
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      // TODO: Connect to backend to check in
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${registration['studentName']} checked in',
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD6A742),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Text(
                          'Check In',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  // TODO: Show more options or detailed view
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                      color: const Color(0xFFE5E7EB),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.more_horiz,
                    color: Color(0xFF4B5563),
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color valueColor) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF4B5563),
            fontWeight: FontWeight.w500,
            fontFamily: 'Poppins',
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 11,
              color: valueColor,
              fontWeight: FontWeight.w600,
              fontFamily: 'Poppins',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // Empty state widget
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFD6A742).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.inbox_outlined,
                size: 40,
                color: Color(0xFFD6A742),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No registrations found',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
                fontFamily: 'Poppins',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Try changing the filter or search another name',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF4B5563),
                fontFamily: 'Poppins',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Pending':
        return const Color(0xFFF59E0B);
      case 'Confirmed':
        return const Color(0xFF10B981);
      case 'Checked In':
        return const Color(0xFF3B82F6);
      default:
        return const Color(0xFF4B5563);
    }
  }

  Color _getAvatarColor(String letter) {
    final colors = [
      const Color(0xFFD6A742),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFF3B82F6),
      const Color(0xFFEC4899),
      const Color(0xFF8B5CF6),
      const Color(0xFF14B8A6),
      const Color(0xFFF97316),
    ];
    return colors[letter.codeUnitAt(0) % colors.length];
  }
}
