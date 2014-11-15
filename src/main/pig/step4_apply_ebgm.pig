/**
 * Copyright 2011 Cloudera Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/**
 * In the final stage of the pipeline, we apply the fitted model that
 * was created from the output of step 3 to the drug-drug-reaction
 * triples that were the output from step 2. We score each triple using
 * two Pig UDFs: EBGM (Empirical Bayes Geometric Mean), the Empirical
 * Bayes smoothing of the (actual/expected) value, and EBCI, which
 * provides a more conservative estimate of the smoothed (actual/expected)
 * ratio than the mean.
 */

/**
 * Register our jar of UDFs and parameterize the two scoring functions using
 * the output of the model fitting stage. The parameters to the EBGM function
 * are (alpha1, beta1, alpha2, beta2, p), and the parameters to the EBCI
 * function are the same, except we specify the target confidence level as
 * the first argument-- in this case, 0.05.
 */
REGISTER target/ades-0.1.0-jar-with-dependencies.jar;
DEFINE EBGM com.cloudera.science.pig.EBGM(
    '9.386857e+00',
    '1.539585e-03',
    '5.182164e-06',
    '6.390573e-01',
    '1.425013e-10');
DEFINE EB05 com.cloudera.science.pig.EBCI('0.05',
    '9.386857e+00',
    '1.539585e-03',
    '5.182164e-06',
    '6.390573e-01',
    '1.425013e-10');

/**
 * Apply the same filtering criteria we did to the data in step 3.
 */
%default FILTER_BELOW 3;

/**
 * Load the output of step 2.
 */
data = LOAD 'aers/drugs2_reacs_actual_expected' USING PigStorage('$') AS (
  d1: chararray, d2: chararray, reac: chararray,
  actual: long, expected: double);
filtered = FILTER data by actual >= $FILTER_BELOW;

/**
 * Apply the scoring functions to the triples.
 */
scaled = FOREACH filtered GENERATE d1, d2, reac, actual,
    expected, actual/expected as rr, EBGM(actual, expected) as ebgm,
    EB05(actual, expected) as eb05;

/**
 * Filter any triples that did not have an eb05 score of at least 2.0, and
 * order the remaining triples by descending geometric mean.
 */
interesting = FILTER scaled BY eb05 >= 2.0;
ordered = ORDER interesting BY ebgm DESC;
STORE ordered INTO 'aers/scored_drugs2_reacs' USING PigStorage('$');
