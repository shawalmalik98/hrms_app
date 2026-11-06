import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../auth/presentation/profile_screen.dart';
import '../../leave/presentation/leave_tab.dart';
import '../../leave/presentation/wfh_tab.dart';
import 'advance_screen.dart';
import 'help_desk_screen.dart';
import 'loan_screen.dart';
import 'payslip_screen.dart';
import 'reimbursement_screen.dart';
import 'resignation_screen.dart';
import 'service_widgets.dart';

/// "More": the employee's money related requests and payslips.
class ServicesTab extends StatelessWidget {
  const ServicesTab({super.key});

  static const _items = <(IconData, String, String, Widget)>[
    (
      Icons.person_rounded,
      'My Profile',
      'Your personal and work details',
      ProfileScreen(),
    ),
    (
      Icons.beach_access_rounded,
      'Leave',
      'Apply for leave, see your requests',
      _LeavePage(),
    ),
    (
      Icons.home_work_rounded,
      'Work From Home',
      'Request a work from home day',
      _WfhPage(),
    ),
    (
      Icons.payments_rounded,
      'Advance Salary',
      'Ask for part of your salary early',
      AdvanceScreen(),
    ),
    (
      Icons.receipt_rounded,
      'Reimbursement',
      'Claim your expenses back',
      ReimbursementScreen(),
    ),
    (
      Icons.account_balance_rounded,
      'Loan',
      'Request a loan, track repayment',
      LoanScreen(),
    ),
    (
      Icons.exit_to_app_rounded,
      'Resignation',
      'Place or view your resignation',
      ResignationScreen(),
    ),
    (
      Icons.support_agent_rounded,
      'Help Desk',
      'Raise a ticket and follow it',
      HelpDeskScreen(),
    ),
    (
      Icons.receipt_long_rounded,
      'Payslips',
      'Download your monthly payslips',
      PayslipScreen(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      // The page ends above the bottom bar, so a small gap is all it needs.
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        for (var i = 0; i < _items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FadeInUp(
              index: i,
              child: AppCard(
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => _items[i].$4)),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(_items[i].$1, color: Colors.white),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _items[i].$2,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: AppColors.navy,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _items[i].$3,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Leave as a page of its own (with an app bar), opened from More.
class _LeavePage extends StatelessWidget {
  const _LeavePage();

  @override
  Widget build(BuildContext context) =>
      const ServiceScaffold(title: 'Leave', body: LeaveTab());
}

/// Work from home as a page of its own (with an app bar), opened from More.
class _WfhPage extends StatelessWidget {
  const _WfhPage();

  @override
  Widget build(BuildContext context) =>
      const ServiceScaffold(title: 'Work From Home', body: WfhTab());
}
