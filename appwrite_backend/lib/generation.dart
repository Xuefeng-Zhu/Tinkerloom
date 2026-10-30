part of 'service.dart';

extension _GenerationRuntime on PlatformService {
  bool _activeGeneration(Row job) =>
      {'queued', 'generating', 'validating'}.contains(job['status']);

  Future<Row> _generate(String actor, Row input) async {
    _inputKeys(input, {
      'op',
      'appId',
      'operationId',
      'expectedRevision',
      'expectedVersionId',
      'request',
      'startFromScratch',
    });
    final expected = _revision(input['expectedRevision']);
    if (!input.containsKey('expectedVersionId') ||
        input['startFromScratch'] is! bool)
      throw const ServiceException('invalid_request', 400);
    final baseId = _versionId(input['expectedVersionId']);
    final request = input['request'];
    if (request is! String ||
        request.trim().isEmpty ||
        utf8.encode(request).length > spec.Limits.promptBytes)
      throw const ServiceException('invalid_request', 400);
    final response = await _mutate(
      actor,
      input,
      'build',
      (tx, access) async {
        _specEngine(access);
        if (access.role != 'owner' && access.app['specVersionId'] == null)
          throw const ServiceException('not_found', 404);
        if (aiProvider == null)
          throw const ServiceException('provider_unavailable', 409);
        if (access.app['specVersionId'] != baseId)
          throw const ServiceException('definition_conflict', 409);
        final prior = await _specDraft(actor, access, tx);
        if ((prior?['revision'] ?? 0) != expected || expected >= 2147483646)
          throw const ServiceException('revision_conflict', 409);
        if (prior != null &&
            prior['publishedVersionId'] == null &&
            prior['baseVersionId'] != baseId)
          throw const ServiceException('definition_conflict', 409);
        final sessionId = _identity('g', [access.app[r'$id'] as String, actor]);
        final session = await store.get(
          'generation_sessions',
          sessionId,
          transactionId: tx,
        );
        final editing =
            baseId != null ||
            input['startFromScratch'] == false ||
            session?['generationEstablished'] == true;
        spec.AppSpec? base;
        if (prior != null && prior['publishedVersionId'] == null)
          base = spec.AppSpec.parse(prior['specJson'] as String);
        else if (baseId != null)
          base = (await _specVersion(access, baseId, tx)).definition;
        if (editing && base == null)
          throw const ServiceException('invalid_request', 400);
        final limits = await _stageActorLimit(actor, tx);
        final active = limits['activeGenerationJobId'];
        if (active != null) {
          final job = await store.get(
            'generation_jobs',
            active as String,
            transactionId: tx,
          );
          if (job != null && _activeGeneration(job))
            throw const ServiceException('generation_active', 409);
        }
        final since = clock()
            .toUtc()
            .subtract(const Duration(days: 1))
            .millisecondsSinceEpoch;
        final times =
            ((jsonDecode((limits['generationTimesJson'] as String?) ?? '[]')
                        as List)
                    .cast<int>())
                .where((time) => time >= since)
                .toList();
        if (times.length >= 30)
          throw const ServiceException('quota_exceeded', 429);
        final jobId = _identity('j', [
          access.app[r'$id'] as String,
          actor,
          input['operationId'] as String,
        ]);
        final mutation = expected + 1;
        if (prior != null)
          await store.update('spec_drafts', prior[r'$id'] as String, {
            'revision': mutation,
            'publishedVersionId': null,
            'baseVersionId': baseId,
            if (base != null) 'specJson': base.canonical,
            if (base != null) 'candidateHash': base.hash,
          }, transactionId: tx);
        final job = await store.create('generation_jobs', jobId, {
          'workspaceId': access.app['workspaceId'],
          'appId': access.app[r'$id'],
          'actorId': actor,
          'draftId': _identity('s', [access.app[r'$id'] as String, actor]),
          'mutation': mutation,
          'draftAbsent': prior == null,
          'baseVersionId': baseId,
          'baseCandidateHash': base?.hash,
          'baseSpecJson': base?.canonical,
          'status': 'queued',
          'mode': editing ? 'edit' : 'create',
          'requestText': request,
          'promptVersion': 'tinkerloom-v1-typed-customization-21',
          'attempts': 0,
          'leaseGeneration': 0,
          'leaseUntil': null,
          'nextAttemptAt': _now(),
          'diagnostics': '',
          'usageJson': '{}',
          'repairJson': null,
          'compilationJson': null,
          'failureCategory': null,
          'provider': null,
          'model': null,
          'createdAt': _now(),
          'updatedAt': _now(),
        }, transactionId: tx);
        final sessionData = <String, dynamic>{
          'workspaceId': access.app['workspaceId'],
          'appId': access.app[r'$id'],
          'actorId': actor,
          'latestJobId': jobId,
          'generationEstablished': session?['generationEstablished'] == true,
        };
        if (session == null) {
          await store.create(
            'generation_sessions',
            sessionId,
            sessionData,
            transactionId: tx,
          );
        } else {
          await store.update(
            'generation_sessions',
            sessionId,
            sessionData,
            transactionId: tx,
          );
        }
        times.add(clock().toUtc().millisecondsSinceEpoch);
        await store.update('actor_limits', limits[r'$id'] as String, {
          'activeGenerationJobId': jobId,
          'generationTimesJson': jsonEncode(times),
        }, transactionId: tx);
        await _queueDispatch(
          'generation',
          jobId,
          access.app[r'$id'] as String,
          clock().toUtc(),
          tx,
        );
        final current = await _specChanged(
          actor,
          access,
          input['operationId'] as String,
          'spec.generate',
          tx,
        );
        return {
          'generation': _publicGeneration(job),
          'app': await _publicSpecApp(actor, current, tx),
        };
      },
      requestBytes: _specRequestBytes,
      responseBytes: _specResponseBytes,
    );
    final job = response['generation'] as Row;
    if (job['status'] == 'queued')
      await _wakeGeneration(job['id'] as String, _time(job['nextAttemptAt']));
    return response;
  }

  Future<bool> _generationCurrent(Row job, AppAccess access, String tx) async {
    if (access.archived ||
        access.app['specVersionId'] != job['baseVersionId'] ||
        !await _workerHasAccess(
          access,
          job['actorId'] as String,
          tx,
          builder: true,
        ))
      return false;
    final session = await store.get(
      'generation_sessions',
      _identity('g', [job['appId'] as String, job['actorId'] as String]),
      transactionId: tx,
    );
    if (session?['latestJobId'] != job[r'$id']) return false;
    final draft = await store.get(
      'spec_drafts',
      job['draftId'] as String,
      transactionId: tx,
    );
    if (job['draftAbsent'] == true) return draft == null;
    return draft != null &&
        draft['appId'] == job['appId'] &&
        draft['actorId'] == job['actorId'] &&
        draft['revision'] == job['mutation'] &&
        draft['candidateHash'] == job['baseCandidateHash'] &&
        draft['baseVersionId'] == job['baseVersionId'] &&
        draft['publishedVersionId'] == null;
  }

  Future<Row?> _claimGenerationSlot(String jobId, String tx) async {
    for (var index = 0; index < 2; index++) {
      final id = 'generation-$index';
      final old = await store.get('worker_leases', id, transactionId: tx);
      if (old != null &&
          old['holderJobId'] != null &&
          _time(old['leaseUntil']).isAfter(clock().toUtc()))
        continue;
      final data = <String, dynamic>{
        'holderJobId': jobId,
        'generation': ((old?['generation'] as int?) ?? 0) + 1,
        'leaseUntil': clock()
            .toUtc()
            .add(const Duration(seconds: 120))
            .toIso8601String(),
        'guard': _nonce(),
      };
      return old == null
          ? store.create('worker_leases', id, data, transactionId: tx)
          : store.update('worker_leases', id, data, transactionId: tx);
    }
    return null;
  }

  Future<void> _releaseGenerationSlot(Row slot) async {
    try {
      await _workerTransaction((tx) async {
        final current = await store.get(
          'worker_leases',
          slot[r'$id'] as String,
          transactionId: tx,
        );
        if (current == null ||
            current['holderJobId'] != slot['holderJobId'] ||
            current['generation'] != slot['generation'])
          return;
        await store.update('worker_leases', slot[r'$id'] as String, {
          'holderJobId': null,
          'guard': _nonce(),
        }, transactionId: tx);
      });
    } catch (_) {
      /* expiry is the durable fallback */
    }
  }

  Future<void> _runGeneration(String jobId) async {
    final initial = await store.get('generation_jobs', _validId(jobId));
    if (initial == null ||
        !_activeGeneration(initial) ||
        _time(initial['nextAttemptAt']).isAfter(clock().toUtc()))
      return;
    final claimed = await _workerTransaction<(Row, Row)?>((tx) async {
      final access = await _workerStage(initial['appId'] as String, tx);
      final job = await store.get('generation_jobs', jobId, transactionId: tx);
      if (job == null ||
          !_activeGeneration(job) ||
          _time(job['nextAttemptAt']).isAfter(clock().toUtc()) ||
          job['leaseUntil'] != null &&
              _time(job['leaseUntil']).isAfter(clock().toUtc()))
        return null;
      if ({'generating', 'validating'}.contains(job['status'])) {
        // A crashed or timed-out worker may already have sent its request.
        // Without provider idempotency evidence, reclaiming it risks duplicate spend.
        await store.update('generation_jobs', jobId, {
          'status': 'failed',
          'failureCategory': 'indeterminate',
          'diagnostics':
              'The previous AI request did not finish before its worker lease expired. Its outcome is unknown.',
          'repairJson': null,
          'leaseUntil': null,
          'updatedAt': _now(),
        }, transactionId: tx);
        await _clearActorGeneration(job, tx);
        return null;
      }
      if (!await _generationCurrent(job, access, tx) ||
          (job['attempts'] as int) >= 3) {
        await store.update('generation_jobs', jobId, {
          'status': (job['attempts'] as int) >= 3 ? 'failed' : 'stale',
          'diagnostics': (job['attempts'] as int) >= 3
              ? 'Generation attempt limit reached.'
              : '',
          'repairJson': null,
          'leaseUntil': null,
          'updatedAt': _now(),
        }, transactionId: tx);
        await _clearActorGeneration(job, tx);
        return null;
      }
      final slot = await _claimGenerationSlot(jobId, tx);
      if (slot == null) return null;
      final updated = await store.update('generation_jobs', jobId, {
        'status': 'generating',
        'attempts': (job['attempts'] as int) + 1,
        'leaseGeneration': (job['leaseGeneration'] as int) + 1,
        'leaseUntil': slot['leaseUntil'],
        'updatedAt': _now(),
      }, transactionId: tx);
      return (updated, slot);
    });
    if (claimed == null) return;
    final (job, slot) = claimed;
    spec.AppSpec? candidate;
    ai.AiResult? result;
    compiler.CompiledGeneratedCreation? compilation;
    String? failure, category;
    bool? retryable;
    var providerCallStarted = false;
    Duration? retryAfter;
    Row? priorRepair;
    try {
      if (aiProvider == null)
        throw const ai.AiResponseException(
          'provider_unavailable',
          'AI provider is not configured. Templates remain available.',
          retryable: false,
        );
      final base = job['baseSpecJson'] == null
          ? spec.AppSpec.parse(ai.creationReferenceJson)
          : spec.AppSpec.parse(job['baseSpecJson'] as String);
      final storedRepair = job['repairJson'] == null
          ? null
          : jsonObject(
              jsonDecode(job['repairJson'] as String),
              'invalid_request',
            );
      if (storedRepair != null &&
          storedRepair['jobId'] == jobId &&
          storedRepair['mutation'] == job['mutation'] &&
          storedRepair['baseCandidateHash'] == job['baseCandidateHash'] &&
          storedRepair['baseVersionId'] == job['baseVersionId'] &&
          storedRepair['mode'] == job['mode'])
        priorRepair = storedRepair;
      providerCallStarted = true;
      result = await aiProvider!.generate(
        job['requestText'] as String,
        base,
        editing: job['mode'] == 'edit',
        diagnostics: priorRepair != null
            ? [priorRepair['diagnostics'] as String]
            : (job['diagnostics'] as String).isEmpty
            ? []
            : [job['diagnostics'] as String],
        rejectedOutput: priorRepair?['output'] as String?,
      );
      final validLease = await _workerTransaction((tx) async {
        await _workerStage(job['appId'] as String, tx);
        final current = await store.get(
          'generation_jobs',
          jobId,
          transactionId: tx,
        );
        if (current == null ||
            current['leaseGeneration'] != job['leaseGeneration'] ||
            current['leaseUntil'] == null ||
            !_time(current['leaseUntil']).isAfter(clock().toUtc()))
          return false;
        await store.update('generation_jobs', jobId, {
          'status': 'validating',
          'updatedAt': _now(),
        }, transactionId: tx);
        return true;
      });
      if (!validLease) return;
      final output = ai.parseAiOutput(result.text);
      if (output['unsupported'] is String)
        throw const ai.AiResponseException(
          'unsupported',
          'Requested capability is unavailable. Choose supported features.',
          retryable: false,
        );
      if (job['mode'] == 'edit') {
        spec.keys(output, {'patches'}, 'edit output');
        candidate = base;
        for (final patch in spec.array(output['patches'], 'patches', 10))
          candidate = candidate!.patch(
            jsonObject(patch, 'invalid_spec'),
            () => 'id_${_nonce().substring(0, 16)}',
          );
        final errors = base.compatibilityErrors(candidate!);
        if (errors.isNotEmpty) throw spec.SpecException(errors.join(' '));
      } else {
        try {
          compilation = compiler.compileGeneratedCreation(
            jsonEncode(output),
            rawOutput: result.text,
          );
          candidate = compilation.spec;
        } on spec.SpecException catch (error) {
          final metadata = repair.creationRawRepairMetadata(
            output,
            request: job['requestText'] as String,
          );
          throw spec.SpecException(
            [
              error.message,
              ...(metadata['rawDiagnostics'] as List? ?? []).cast<String>(),
            ].join(' '),
          );
        }
        if (candidate.appearance == null)
          candidate = candidate.patch({
            'type': 'SetAppearance',
            'appearance': {'style': 'clean'},
          }, () => throw StateError('Appearance must not allocate IDs'));
      }
      quality.validateGeneratedExperience(
        candidate,
        baseline: job['mode'] == 'edit' ? base : null,
      );
      if (job['mode'] != 'edit')
        requirements.GenerationRequirements.fromRequest(
          job['requestText'] as String,
        ).validate(candidate);
      final allowedImages = job['mode'] == 'edit' && job['baseSpecJson'] != null
          ? _definitionImages(base)
          : <String>{};
      if (!allowedImages.containsAll(_definitionImages(candidate)))
        throw const ai.AiResponseException(
          'media_reference',
          'Generated definitions cannot invent private image references. Preserve existing references or omit them.',
        );
    } on ai.AiResponseException catch (error) {
      failure = error.message;
      category = error.kind;
      retryable = error.retryable;
      retryAfter = error.retryAfter;
      if (providerCallStarted &&
          {
            'indeterminate',
            'timeout',
            'transport_error',
            'http_error',
            'rate_limited',
          }.contains(category)) {
        if (error.statusCode == 429 ||
            error.providerErrorType == 'rate_limit_exceeded' ||
            category == 'rate_limited') {
          category = 'rate_limited';
        } else if (category != 'http_error' ||
            error.statusCode == null ||
            error.statusCode == 408 ||
            error.statusCode == 425 ||
            error.statusCode! >= 500) {
          category = 'indeterminate';
        }
        retryable = false;
      }
      // A missing provider result may have consumed a paid request, even when
      // the error itself describes a malformed or incomplete response.
      if (providerCallStarted && result == null) {
        if ({
          'response_size',
          'envelope_json',
          'envelope_shape',
          'content_missing',
        }.contains(category)) {
          category = 'indeterminate';
        }
        retryable = false;
      }
    } on spec.SpecException catch (error) {
      if (providerCallStarted && result == null) {
        failure =
            'The AI request did not complete normally. Its outcome is unknown.';
        category = 'indeterminate';
        retryable = false;
      } else {
        failure = error.message;
        category = 'spec_validation';
      }
    } on FormatException {
      if (providerCallStarted && result == null) {
        failure =
            'The AI request did not complete normally. Its outcome is unknown.';
        category = 'indeterminate';
        retryable = false;
      } else {
        failure = 'The generated definition contains an invalid value format.';
        category = 'value_format';
      }
    } catch (_) {
      failure = providerCallStarted && result == null
          ? 'The AI request did not complete normally. Its outcome is unknown.'
          : 'Generation could not validate the response.';
      category = providerCallStarted && result == null
          ? 'indeterminate'
          : 'unexpected';
      retryable = false;
    } finally {
      await _releaseGenerationSlot(slot);
    }
    final computedCandidate = candidate;
    final finalJob = await _workerTransaction<Row?>((tx) async {
      final access = await _workerStage(job['appId'] as String, tx);
      final current = await store.get(
        'generation_jobs',
        jobId,
        transactionId: tx,
      );
      if (current == null ||
          current['leaseGeneration'] != job['leaseGeneration'] ||
          current['leaseUntil'] == null ||
          !_time(current['leaseUntil']).isAfter(clock().toUtc()))
        return null;
      final stale = !await _generationCurrent(job, access, tx);
      if (!stale && failure == null && computedCandidate != null) {
        try {
          await validateGeneratedMedia(
            job['actorId'] as String,
            access,
            job['baseSpecJson'] == null
                ? null
                : spec.AppSpec.parse(job['baseSpecJson'] as String),
            computedCandidate,
            tx,
          );
        } on ServiceException {
          failure =
              'An existing private image is no longer available. Review the source images before retrying.';
          category = 'media_reference';
          retryable = false;
        }
      }
      final failed = failure != null;
      final terminal =
          stale ||
          !failed ||
          (current['attempts'] as int) >= 3 ||
          category == 'unsupported' ||
          retryable == false;
      final status = stale
          ? 'stale'
          : failed
          ? (terminal ? 'failed' : 'queued')
          : 'preview ready';
      Row? repairContext;
      if (status == 'queued' &&
          {
            'output_json',
            'output_shape',
            'spec_validation',
            'value_format',
            'media_reference',
          }.contains(category) &&
          result != null &&
          result.text.isNotEmpty &&
          utf8.encode(result.text).length <= spec.Limits.definitionBytes) {
        repairContext = {
          'jobId': jobId,
          'mutation': job['mutation'],
          'baseCandidateHash': job['baseCandidateHash'],
          'baseVersionId': job['baseVersionId'],
          'mode': job['mode'],
          'attempt': current['attempts'],
          'output': result.text,
          'diagnostics': _limitedDiagnostic(failure!),
        };
      } else if (status == 'queued' &&
          priorRepair != null &&
          (retryable == true ||
              {
                'timeout',
                'http_error',
                'transport_error',
                'envelope_json',
                'envelope_shape',
                'content_missing',
                'completion_stopped',
                'truncated',
                'response_size',
              }.contains(category))) {
        repairContext = priorRepair;
      }
      final usage = Map<String, dynamic>.from(result?.usage ?? {})
        ..remove('_appnestRepair')
        ..remove('_appnestFailureCategory')
        ..remove('_appnestCompilation');
      final next = clock().toUtc().add(
        Duration(
          seconds: max(
            1 << (current['attempts'] as int),
            retryAfter == null ? 0 : retryAfter.inSeconds.clamp(1, 120),
          ),
        ),
      );
      if (!stale && !failed && computedCandidate != null) {
        final data = <String, dynamic>{
          'workspaceId': access.app['workspaceId'],
          'appId': access.app[r'$id'],
          'actorId': job['actorId'],
          'revision': job['mutation'],
          'baseVersionId': job['baseVersionId'],
          'candidateHash': computedCandidate.hash,
          'specJson': computedCandidate.canonical,
          'publishedVersionId': null,
        };
        final draft = await store.get(
          'spec_drafts',
          job['draftId'] as String,
          transactionId: tx,
        );
        if (draft == null) {
          await store.create(
            'spec_drafts',
            job['draftId'] as String,
            data,
            transactionId: tx,
          );
        } else {
          await store.update(
            'spec_drafts',
            job['draftId'] as String,
            data,
            transactionId: tx,
          );
        }
        await syncGeneratedMedia(
          job['actorId'] as String,
          access,
          computedCandidate,
          tx,
        );
        await store.update(
          'generation_sessions',
          _identity('g', [job['appId'] as String, job['actorId'] as String]),
          {'generationEstablished': true},
          transactionId: tx,
        );
      }
      final updated = await store.update('generation_jobs', jobId, {
        'status': status,
        'diagnostics': stale ? '' : _limitedDiagnostic(failure ?? ''),
        'failureCategory': category,
        'usageJson': jsonEncode(usage),
        'repairJson': repairContext == null ? null : jsonEncode(repairContext),
        'compilationJson': !stale && !failed && compilation != null
            ? jsonEncode({
                ...compilation.toJson(),
                'finalCandidateHash': computedCandidate!.hash,
              })
            : null,
        'provider': result?.provider,
        'model': result?.model,
        'leaseUntil': null,
        'nextAttemptAt': next.toIso8601String(),
        'updatedAt': _now(),
      }, transactionId: tx);
      if (terminal) await _clearActorGeneration(job, tx);
      if (status == 'queued')
        await _queueDispatch(
          'generation',
          jobId,
          job['appId'] as String,
          next,
          tx,
        );
      return updated;
    });
    if (finalJob?['status'] == 'queued')
      await _wakeGeneration(jobId, _time(finalJob!['nextAttemptAt']));
  }

  Future<Row> _drainGenerations(int maximum) async {
    if (maximum < 1 || maximum > 2)
      throw ArgumentError('Generation batch must be1..2');
    final jobs = <Row>[];
    for (final status in ['queued', 'generating', 'validating'])
      jobs.addAll(
        await _workerRows('generation_jobs', {'status': status}, null),
      );
    final due = jobs
        .where(
          (job) =>
              !_time(job['nextAttemptAt']).isAfter(clock().toUtc()) &&
              (job['leaseUntil'] == null ||
                  !_time(job['leaseUntil']).isAfter(clock().toUtc())),
        )
        .take(maximum)
        .toList();
    await Future.wait(due.map((job) => _runGeneration(job[r'$id'] as String)));
    return {'considered': due.length};
  }

  Future<Row> _getGeneration(String actor, Row input) async {
    _inputKeys(input, {'op', 'appId', 'jobId'});
    final id = _validId(input['jobId']);
    return _specRead(actor, _validId(input['appId']), (access, tx) async {
      _require(access, 'build', writable: false);
      final job = await store.get('generation_jobs', id, transactionId: tx);
      if (job == null ||
          job['actorId'] != actor ||
          job['appId'] != access.app[r'$id'] ||
          job['workspaceId'] != access.app['workspaceId'])
        throw const ServiceException('not_found', 404);
      return {
        'generation': _publicGeneration(job),
        'app': await _publicSpecApp(actor, access, tx),
      };
    });
  }

  Future<Row> _keepPrevious(String actor, Row input) async {
    _inputKeys(input, {
      'op',
      'appId',
      'jobId',
      'expectedRevision',
      'operationId',
    });
    final id = _validId(input['jobId']),
        expected = _revision(input['expectedRevision']);
    return _mutate(
      actor,
      input,
      'build',
      (tx, access) async {
        final job = await store.get('generation_jobs', id, transactionId: tx),
            draft = await _specDraft(actor, access, tx);
        final session = await store.get(
          'generation_sessions',
          _identity('g', [access.app[r'$id'] as String, actor]),
          transactionId: tx,
        );
        if (job == null ||
            job['actorId'] != actor ||
            job['appId'] != access.app[r'$id'] ||
            job['mode'] != 'edit' ||
            job['status'] != 'failed')
          throw const ServiceException('invalid_request', 400);
        if (draft == null ||
            draft['revision'] != expected ||
            job['mutation'] != expected ||
            session?['latestJobId'] != id ||
            draft['baseVersionId'] != access.app['specVersionId'] ||
            expected >= 2147483646)
          throw const ServiceException('revision_conflict', 409);
        await store.update('spec_drafts', draft[r'$id'] as String, {
          'revision': expected + 1,
        }, transactionId: tx);
        await store.update('generation_sessions', session![r'$id'] as String, {
          'latestJobId': null,
        }, transactionId: tx);
        final current = await _specChanged(
          actor,
          access,
          input['operationId'] as String,
          'spec.keepPrevious',
          tx,
        );
        return {
          'generation': _publicGeneration(job),
          'app': await _publicSpecApp(actor, current, tx),
        };
      },
      requestBytes: _specRequestBytes,
      responseBytes: _specResponseBytes,
    );
  }

  Future<Row> _guidance(String actor, Row input) async {
    _inputKeys(input, {'op', 'workspaceId', 'appId', 'request'});
    final request = input['request'];
    if (request is! String ||
        request.trim().isEmpty ||
        request.length > 2000 ||
        utf8.encode(request).length > 4000)
      throw const ServiceException('invalid_request', 400);
    if (guidanceProvider == null)
      throw const ServiceException('provider_unavailable', 409);
    final workspace = await _workspace(actor, input['workspaceId']);
    spec.AppSpec? definition;
    if (input['appId'] != null) {
      final access = await _access(actor, _validId(input['appId']));
      _require(access, 'build');
      _specEngine(access);
      if (access.app['workspaceId'] != workspace[r'$id'])
        throw const ServiceException('not_found', 404);
      final draft = await _specDraft(actor, access, null);
      if (draft != null)
        definition = spec.AppSpec.parse(draft['specJson'] as String);
    }
    await _workerTransaction((tx) async {
      final current = await _workspace(
        actor,
        workspace[r'$id'],
        transactionId: tx,
      );
      await store.update('workspaces', current[r'$id'] as String, {
        'guard': _nonce(),
      }, transactionId: tx);
      final limits = await _stageActorLimit(actor, tx);
      final since = clock()
          .toUtc()
          .subtract(const Duration(days: 1))
          .millisecondsSinceEpoch;
      final times =
          ((jsonDecode((limits['guidanceTimesJson'] as String?) ?? '[]')
                      as List)
                  .cast<int>())
              .where((time) => time >= since)
              .toList();
      if (times.length >= 20)
        throw const ServiceException('quota_exceeded', 429);
      times.add(clock().toUtc().millisecondsSinceEpoch);
      await store.update('actor_limits', limits[r'$id'] as String, {
        'guidanceTimesJson': jsonEncode(times),
      }, transactionId: tx);
    });
    try {
      final questions = await guidanceProvider!.suggestQuestions(
        request,
        definition: definition,
      );
      await _workspace(actor, workspace[r'$id']);
      if (input['appId'] != null)
        _require(await _access(actor, input['appId'] as String), 'build');
      return {
        'questions': questions.map((question) => question.toJson()).toList(),
      };
    } catch (error) {
      if (error is ServiceException) rethrow;
      throw const ServiceException('provider_unavailable', 409);
    }
  }
}
